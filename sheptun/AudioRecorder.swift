import Foundation
import AVFoundation
import CoreAudio
import AppKit

class AudioRecorder: NSObject, ObservableObject {
    static let shared = AudioRecorder()
    
    @Published var isRecording = false
    @Published var recordingTime: TimeInterval = 0
    @Published var audioLevel: Float = 0.0
    
    private var audioRecorder: AVAudioRecorder?
    private var timer: Timer?
    private var recordingStartTime: Date?
    private let logger = Logger.shared
    private let settings = SettingsManager.shared
    
    // Audio level monitoring
    private var audioMonitor: AudioLevelMonitor?
    
    // Recording file URL
    private var recordingFileURL: URL?
    
    // Task management
    private var setupTask: Task<Void, Never>?
    
    private override init() {
        super.init()
    }
    
    // Function to start recording with a specific microphone ID
    func startRecording(microphoneID: String) -> Bool {
        // Cancel any existing setup task
        setupTask?.cancel()
        
        // Check if we're already recording
        if isRecording {
            logger.log("Recording is already in progress", level: .warning)
            return false
        }
        
        // Start the recording setup process
        setupTask = Task { [weak self] in
            guard let self = self else { return }
            
            do {
                // Create a URL for the audio recording
                let tempDir = NSTemporaryDirectory()
                recordingFileURL = URL(fileURLWithPath: tempDir).appendingPathComponent("temp_recording.m4a")
                
                // Configure audio recording settings for OpenAI compatibility
                let recordSettings: [String: Any] = [
                    AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                    AVSampleRateKey: 44100,
                    AVNumberOfChannelsKey: 1,
                    AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
                ]
                
                // Try to set the selected microphone device
                if !microphoneID.isEmpty && microphoneID != "default", let deviceIDInt = UInt32(microphoneID) {
                    var deviceID = AudioDeviceID(deviceIDInt)
                    self.logger.log("Setting recording device to ID: \(deviceID)", level: .info)
                    
                    // On macOS, use Core Audio to set the default input device
                    var propertyAddress = AudioObjectPropertyAddress(
                        mSelector: kAudioHardwarePropertyDefaultInputDevice,
                        mScope: kAudioObjectPropertyScopeGlobal,
                        mElement: kAudioObjectPropertyElementMain
                    )
                    
                    // Set the default input device
                    let status = AudioObjectSetPropertyData(
                        AudioObjectID(kAudioObjectSystemObject),
                        &propertyAddress,
                        0,
                        nil,
                        UInt32(MemoryLayout<AudioDeviceID>.size),
                        &deviceID
                    )
                    
                    if status != noErr {
                        self.logger.log("Warning: Could not set default input device, status: \(status)", level: .warning)
                    } else {
                        self.logger.log("Successfully set default input device to ID: \(deviceID)", level: .info)
                    }
                    
                    // Set up audio level monitoring
                    await MainActor.run {
                        self.setupAudioMonitoring(deviceID: deviceIDInt)
                    }
                } else {
                    self.logger.log("Using system default microphone", level: .info)
                    // Try to get system default microphone ID for monitoring
                    if let defaultIDStr = self.settings.getDefaultSystemMicrophoneID(), let defaultID = UInt32(defaultIDStr) {
                        await MainActor.run {
                            self.setupAudioMonitoring(deviceID: defaultID)
                        }
                    }
                }
                
                // Initialize audio recorder
                guard let recordingFileURL = recordingFileURL else {
                    self.logger.log("Failed to create recording file URL", level: .error)
                    return
                }
                
                // Delete any existing file at this URL
                if FileManager.default.fileExists(atPath: recordingFileURL.path) {
                    try FileManager.default.removeItem(at: recordingFileURL)
                    self.logger.log("Removed existing recording file", level: .debug)
                }
                
                let recorder = try AVAudioRecorder(url: recordingFileURL, settings: recordSettings)
                recorder.delegate = self
                recorder.isMeteringEnabled = true
                
                // Update UI and state on main thread
                await MainActor.run {
                    self.audioRecorder = recorder
                    
                    // Begin recording
                    if recorder.record() {
                        self.isRecording = true
                        self.recordingStartTime = Date()
                        
                        // Start the timer for updating UI
                        self.startTimer()
                        
                        self.logger.log("Started audio recording to file: \(recordingFileURL.path)", level: .info)
                    } else {
                        self.logger.log("Failed to start audio recording", level: .error)
                    }
                }
            } catch {
                await MainActor.run {
                    self.logger.log("Audio session error: \(error.localizedDescription)", level: .error)
                }
            }
        }
        
        // Return true to indicate that recording setup has started
        return true
    }
    
    func stopRecording() {
        // Guard against multiple calls to stopRecording()
        guard isRecording else {
            logger.log("stopRecording() called while not recording, ignoring", level: .debug)
            return
        }
        
        logger.log("stopRecording() called, attempting to stop recording", level: .info)
        
        // Mark as not recording immediately to prevent multiple calls
        isRecording = false
        
        // Safe cleanup in a task to ensure completion
        Task { [weak self] in
            guard let self = self else { return }
            
            // Stop the recording components
            await MainActor.run {
                self.logger.log("Stopping audio recording components...", level: .info)
                
                // Stop the audio recorder
                if let recorder = self.audioRecorder {
                    recorder.stop()
                    self.logger.log("AVAudioRecorder stopped", level: .info)
                } else {
                    self.logger.log("No active AVAudioRecorder to stop", level: .debug)
                }
                self.audioRecorder = nil
                
                // Reset timer
                self.stopTimer()
                
                // Stop audio monitoring
                self.stopAudioMonitoring()
                
                // Log the recording duration
                if let startTime = self.recordingStartTime {
                    let duration = Date().timeIntervalSince(startTime)
                    self.logger.log("Stopped audio recording. Duration: \(String(format: "%.2f", duration)) seconds", level: .info)
                    
                    // Verify the recording file exists and log its size
                    if let fileURL = self.recordingFileURL, FileManager.default.fileExists(atPath: fileURL.path) {
                        do {
                            let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
                            if let fileSize = attributes[.size] as? NSNumber {
                                self.logger.log("Recording saved to file: \(fileURL.path), size: \(fileSize.intValue) bytes", level: .info)
                            }
                        } catch {
                            self.logger.log("Error getting file attributes: \(error.localizedDescription)", level: .warning)
                        }
                    } else {
                        self.logger.log("Warning: Recording file not found after stopping", level: .warning)
                    }
                } else {
                    self.logger.log("Stopped audio recording. Could not calculate duration (no start time)", level: .warning)
                }
                
                // Ensure isRecording state is false
                self.isRecording = false
            }
        }
    }
    
    private func setupAudioMonitoring(deviceID: UInt32) {
        // Stop any existing monitoring
        stopAudioMonitoring()
        
        logger.log("Setting up audio monitoring in recorder for device ID: \(deviceID)", level: .debug)
        
        // Create a new audio monitor
        audioMonitor = AudioLevelMonitor(deviceID: deviceID)
        
        // Start monitoring with handlers
        audioMonitor?.startMonitoring(
            levelUpdateHandler: { [weak self] level in
                DispatchQueue.main.async {
                    self?.audioLevel = level
                }
            },
            errorHandler: { [weak self] error in
                self?.logger.log("Audio monitoring error: \(error)", level: .warning)
                // If monitoring fails, fall back to meter-based levels
                self?.audioLevel = 0
            }
        )
    }
    
    private func stopAudioMonitoring() {
        audioMonitor?.stopMonitoring()
        audioMonitor = nil
    }
    
    private func startTimer() {
        // Create timer to update UI every 0.1 seconds
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            
            // Update recording time
            if let startTime = self.recordingStartTime {
                self.recordingTime = Date().timeIntervalSince(startTime)
            }
            
            // Use audioMonitor for levels, but if that's not working, fall back to meters
            if self.audioLevel <= 0.01 {
                self.updateAudioLevels()
            }
        }
    }
    
    private func stopTimer() {
        timer?.invalidate()
        timer = nil
        recordingStartTime = nil
    }
    
    private func updateAudioLevels() {
        guard let recorder = audioRecorder, recorder.isRecording else {
            return
        }
        
        recorder.updateMeters()
        
        // Get the average power from the audio recorder
        let averagePower = recorder.averagePower(forChannel: 0)
        
        // Convert to a 0-1 scale (audio is in dB from -160 to 0)
        // Using a normalized scale for better visualization
        let normalizedValue = (averagePower + 50) / 50
        
        // Clamp between 0 and 1
        audioLevel = max(0, min(normalizedValue, 1))
    }
    

    
    // Get the current recording file URL
    func getRecordingFileURL() -> URL? {
        if let url = recordingFileURL, FileManager.default.fileExists(atPath: url.path) {
            return url
        }
        return nil
    }
    
    // Clean up all resources
    func cleanup() {
        setupTask?.cancel()
        stopAudioMonitoring()
        stopTimer()
        
        if isRecording {
            audioRecorder?.stop()
            audioRecorder = nil
            isRecording = false
        }
    }
    
    // Original method for backward compatibility
    func startRecording() {
        _ = startRecording(microphoneID: settings.selectedMicrophoneID)
    }
    
    // Check if microphone permission is granted
    func checkMicrophonePermission() -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return true
        case .denied, .restricted:
            return false
        case .notDetermined:
            return false
        @unknown default:
            return false
        }
    }
    
    // Request microphone permission
    func requestMicrophonePermission(completion: @escaping (Bool) -> Void) {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            // Already authorized
            completion(true)
            
        case .notDetermined:
            // Permission hasn't been asked yet, so ask
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                DispatchQueue.main.async {
                    completion(granted)
                }
            }
            
        case .denied, .restricted:
            // Permission was denied, open system settings
            let alert = NSAlert()
            alert.messageText = "Microphone Access Required"
            alert.informativeText = "Sheptun needs access to your microphone to function. Please grant microphone access in System Settings."
            alert.alertStyle = .warning
            alert.addButton(withTitle: "Open Settings")
            alert.addButton(withTitle: "Cancel")
            
            let response = alert.runModal()
            if response == .alertFirstButtonReturn {
                // Open system settings
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
                    NSWorkspace.shared.open(url)
                }
            }
            completion(false)
            
        @unknown default:
            completion(false)
        }
    }
}

extension AudioRecorder: AVAudioRecorderDelegate {
    func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        if !flag {
            logger.log("Audio recording finished unsuccessfully", level: .warning)
        }
        
        // We discard the recording, but could save it here if needed
        isRecording = false
    }
    
    func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        if let error = error {
            logger.log("Audio recording encoding error: \(error.localizedDescription)", level: .error)
        }
        stopRecording()
    }
} 