import Foundation
import AVFoundation

class AudioRecorder: NSObject, ObservableObject {
    static let shared = AudioRecorder()
    
    @Published var isRecording = false
    @Published var recordingTime: TimeInterval = 0
    @Published var audioLevel: Float = 0.0
    
    private var audioRecorder: AVAudioRecorder?
    private var timer: Timer?
    private var recordingStartTime: Date?
    private let logger = Logger.shared
    
    // For audio level monitoring
    private var audioLevelTimer: Timer?
    
    private override init() {
        super.init()
    }
    
    func startRecording() {
        do {
            // Create a temporary URL for the audio recording
            let tempDir = NSTemporaryDirectory()
            let tempURL = URL(fileURLWithPath: tempDir).appendingPathComponent("temp_recording.m4a")
            
            // Configure audio recording settings
            let settings = [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey: 44100,
                AVNumberOfChannelsKey: 1,
                AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
            ]
            
            // Initialize audio recorder
            audioRecorder = try AVAudioRecorder(url: tempURL, settings: settings)
            audioRecorder?.delegate = self
            audioRecorder?.isMeteringEnabled = true
            
            // Begin recording
            if audioRecorder?.record() ?? false {
                isRecording = true
                recordingStartTime = Date()
                
                // Start the timer for updating UI
                startTimer()
                
                logger.log("Started audio recording", level: .info)
            } else {
                logger.log("Failed to start audio recording", level: .error)
            }
        } catch {
            logger.log("Audio recording error: \(error.localizedDescription)", level: .error)
        }
    }
    
    func stopRecording() {
        // Stop recording
        audioRecorder?.stop()
        audioRecorder = nil
        
        // Stop and reset the timer
        stopTimer()
        
        isRecording = false
        
        // Log recording duration
        let duration = recordingTime
        logger.log("Stopped audio recording. Duration: \(String(format: "%.2f", duration)) seconds", level: .info)
        
        // Reset recording timer display
        recordingTime = 0
        audioLevel = 0
    }
    
    private func startTimer() {
        // Create timer to update UI every 0.1 seconds
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            
            // Update recording time
            if let startTime = self.recordingStartTime {
                self.recordingTime = Date().timeIntervalSince(startTime)
            }
            
            // Update audio level meters
            self.updateAudioLevels()
        }
    }
    
    private func stopTimer() {
        timer?.invalidate()
        timer = nil
        recordingStartTime = nil
    }
    
    private func updateAudioLevels() {
        guard let recorder = audioRecorder, recorder.isRecording else {
            audioLevel = 0
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
        if isRecording {
            // Generate random values between 0.1 and 0.8 for a realistic audio simulation
            audioLevel = Float.random(in: 0.1...0.8)
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