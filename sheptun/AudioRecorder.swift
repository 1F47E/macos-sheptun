import Foundation
import AVFoundation
import CoreAudio

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
    
    // MARK: - Audio Buffer for Streaming
    
    private var isAudioEngineSetup = false
    private var audioEngine: AVAudioEngine?
    private var inputNode: AVAudioInputNode?
    private var latestAudioBuffer: Data?
    private var audioFormat: AVAudioFormat?
    
    // Task management
    private var setupTask: Task<Void, Never>?
    
    private override init() {
        super.init()
    }
    
    func startRecording() {
        // Cancel any existing setup task
        setupTask?.cancel()
        
        setupTask = Task { [weak self] in
            guard let self = self else { return }
            
            do {
                // Check if we're already recording first
                if self.isRecording {
                    self.logger.log("Recording is already in progress", level: .warning)
                    return
                }
                
                // Set up the audio engine for streaming - done first as it's critical
                try await self.setupAudioEngineAsync()
                
                // Create a temporary URL for the audio recording
                let tempDir = NSTemporaryDirectory()
                let tempURL = URL(fileURLWithPath: tempDir).appendingPathComponent("temp_recording.m4a")
                
                // Configure audio recording settings
                let recordSettings = [
                    AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                    AVSampleRateKey: 44100,
                    AVNumberOfChannelsKey: 1,
                    AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
                ]
                
                // Try to set the selected microphone device if available
                if !self.settings.selectedMicrophoneID.isEmpty, let deviceIDInt = UInt32(self.settings.selectedMicrophoneID) {
                    var deviceID = AudioDeviceID(deviceIDInt)
                    self.logger.log("Setting recording device to ID: \(deviceID)", level: .info)
                    
                    // On macOS, you can use Core Audio to set the default input device before recording
                    var propertyAddress = AudioObjectPropertyAddress(
                        mSelector: kAudioHardwarePropertyDefaultInputDevice,
                        mScope: kAudioObjectPropertyScopeGlobal,
                        mElement: kAudioObjectPropertyElementMain
                    )
                    
                    // Try to set the default input device
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
                    
                    // Set up real-time audio level monitoring using the AudioLevelMonitor 
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
                let recorder = try AVAudioRecorder(url: tempURL, settings: recordSettings)
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
                        
                        self.logger.log("Started audio recording", level: .info)
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
    }
    
    func stopRecording() {
        // Cancel any setup task
        setupTask?.cancel()
        
        Task { [weak self] in
            guard let self = self else { return }
            
            await MainActor.run {
                // Stop the audio engine
                self.stopAudioEngine()
                
                // Stop recording
                self.audioRecorder?.stop()
                self.audioRecorder = nil
                
                // Stop and reset the timer
                self.stopTimer()
                
                // Stop audio monitoring
                self.stopAudioMonitoring()
                
                self.isRecording = false
                
                // Log recording duration
                let duration = self.recordingTime
                self.logger.log("Stopped audio recording. Duration: \(String(format: "%.2f", duration)) seconds", level: .info)
                
                // Reset recording timer display
                self.recordingTime = 0
                self.audioLevel = 0
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
    
    // Method for simulating audio levels in case permissions aren't granted
    func simulateAudioLevels() {
        // Only use simulation if we don't have real audio levels
        if isRecording && audioLevel <= 0.01 {
            // Generate random values between 0.1 and 0.8 for a realistic audio simulation
            audioLevel = Float.random(in: 0.1...0.8)
        }
    }
    
    // Async version of setupAudioEngineForStreaming
    private func setupAudioEngineAsync() async throws {
        // Check if already set up and running
        if isAudioEngineSetup && audioEngine?.isRunning == true {
            return
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            do {
                // Set up audio engine for real-time audio capture
                audioEngine = AVAudioEngine()
                inputNode = audioEngine?.inputNode
                
                // IMPORTANT: Use the native format of the input node instead of creating a custom format
                // This prevents format incompatibility errors that can cause crashes
                guard let inputNode = inputNode else {
                    logger.log("Failed to get input node", level: .error)
                    continuation.resume(throwing: NSError(domain: "AudioRecorder", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to get input node"]))
                    return
                }
                
                // Get the native format from the input node
                let nativeFormat = inputNode.inputFormat(forBus: 0)
                logger.log("Using native input format: \(nativeFormat.description)", level: .info)
                
                // Create a compatible format based on the native format
                // Keeping sample rate the same as native but ensuring it's mono for speech recognition
                let pcmFormat = AVAudioFormat(
                    commonFormat: .pcmFormatInt16,
                    sampleRate: nativeFormat.sampleRate,
                    channels: 1,
                    interleaved: true
                )
                
                audioFormat = pcmFormat
                
                guard let format = pcmFormat else {
                    logger.log("Failed to create audio format", level: .error)
                    continuation.resume(throwing: NSError(domain: "AudioRecorder", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to create audio format"]))
                    return
                }
                
                // Install tap on input node to capture audio
                inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, time in
                    guard let self = self else { return }
                    
                    // Convert audio buffer to Data
                    let channelData = buffer.int16ChannelData?[0]
                    let channelDataCount = Int(buffer.frameLength)
                    
                    if let channelData = channelData {
                        let data = Data(bytes: channelData, count: channelDataCount * 2) // 2 bytes per Int16
                        self.latestAudioBuffer = data
                    }
                }
                
                // Start the audio engine
                try audioEngine?.start()
                isAudioEngineSetup = true
                logger.log("Audio engine started for streaming", level: .info)
                
                continuation.resume()
            } catch {
                logger.log("Failed to start audio engine: \(error)", level: .error)
                continuation.resume(throwing: error)
            }
        }
    }
    
    func setupAudioEngineForStreaming() {
        // This synchronous version is kept for backward compatibility
        // Set up audio engine for real-time audio capture
        audioEngine = AVAudioEngine()
        inputNode = audioEngine?.inputNode
        
        guard let inputNode = self.inputNode else {
            logger.log("Failed to get input node", level: .error)
            return
        }
        
        // Get the native format from the input node
        let nativeFormat = inputNode.inputFormat(forBus: 0)
        logger.log("Using native input format: \(nativeFormat.description)", level: .info)
        
        // Create a compatible format based on the native format
        let pcmFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: nativeFormat.sampleRate,
            channels: 1,
            interleaved: true
        )
        
        audioFormat = pcmFormat
        
        guard let format = pcmFormat else {
            logger.log("Failed to create audio format", level: .error)
            return
        }
        
        // Install tap on input node to capture audio
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, time in
            guard let self = self else { return }
            
            // Convert audio buffer to Data
            let channelData = buffer.int16ChannelData?[0]
            let channelDataCount = Int(buffer.frameLength)
            
            if let channelData = channelData {
                let data = Data(bytes: channelData, count: channelDataCount * 2) // 2 bytes per Int16
                self.latestAudioBuffer = data
            }
        }
        
        // Start the audio engine
        do {
            try audioEngine?.start()
            isAudioEngineSetup = true
            logger.log("Audio engine started for streaming", level: .info)
        } catch {
            logger.log("Failed to start audio engine: \(error)", level: .error)
        }
    }
    
    func getLatestAudioBuffer() -> Data? {
        // If audio engine is not set up, we'll need to return nil as we can't set it up synchronously here
        if audioEngine == nil || !isAudioEngineSetup {
            logger.log("Audio engine not set up when trying to get latest buffer", level: .warning)
            return nil
        }
        
        // Return the latest captured audio data
        return latestAudioBuffer
    }
    
    func stopAudioEngine() {
        audioEngine?.stop()
        inputNode?.removeTap(onBus: 0)
        audioEngine = nil
        inputNode = nil
        latestAudioBuffer = nil
        isAudioEngineSetup = false
        logger.log("Audio engine stopped", level: .info)
    }
    
    // Clean up all resources
    func cleanup() {
        setupTask?.cancel()
        stopAudioEngine()
        stopAudioMonitoring()
        stopTimer()
        
        if isRecording {
            audioRecorder?.stop()
            audioRecorder = nil
            isRecording = false
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