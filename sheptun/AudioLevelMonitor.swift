import Foundation
import AVFoundation
import CoreAudio

class AudioLevelMonitor {
    private var audioQueue: AudioQueueRef?
    private var timer: Timer?
    private var deviceID: UInt32
    private let logger = Logger.shared
    
    init(deviceID: UInt32) {
        self.deviceID = deviceID
        logger.log("AudioLevelMonitor initialized for device ID: \(deviceID)")
    }
    
    func startMonitoring(levelUpdateHandler: @escaping (Float) -> Void, errorHandler: @escaping (String) -> Void) {
        // First request microphone permission
        requestMicrophonePermission { [weak self] granted in
            guard let self = self else { return }
            
            if granted {
                self.logger.log("Microphone permission granted, setting up audio queue")
                self.setupAudioMonitoring(levelUpdateHandler: levelUpdateHandler, errorHandler: errorHandler)
            } else {
                let errorMsg = "Microphone permission denied"
                self.logger.log(errorMsg, level: .error)
                errorHandler(errorMsg)
            }
        }
    }
    
    private func requestMicrophonePermission(completion: @escaping (Bool) -> Void) {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            // Permission already granted
            logger.log("Microphone permission already granted")
            completion(true)
        case .notDetermined:
            // Request permission
            logger.log("Requesting microphone permission")
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                DispatchQueue.main.async {
                    self.logger.log("Microphone permission request result: \(granted)")
                    completion(granted)
                }
            }
        case .denied, .restricted:
            // Permission denied or restricted
            logger.log("Microphone permission denied or restricted", level: .error)
            completion(false)
        @unknown default:
            logger.log("Unknown microphone permission status", level: .error)
            completion(false)
        }
    }
    
    private func setupAudioMonitoring(levelUpdateHandler: @escaping (Float) -> Void, errorHandler: @escaping (String) -> Void) {
        // Configure audio format
        var audioFormat = AudioStreamBasicDescription(
            mSampleRate: 44100.0,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: UInt32(kLinearPCMFormatFlagIsSignedInteger | kLinearPCMFormatFlagIsPacked),
            mBytesPerPacket: 2,
            mFramesPerPacket: 1,
            mBytesPerFrame: 2,
            mChannelsPerFrame: 1,
            mBitsPerChannel: 16,
            mReserved: 0
        )
        
        // Set up the audio queue
        var propSize = UInt32(MemoryLayout<UInt32>.size)
        var queueStatus = AudioQueueNewInput(
            &audioFormat,
            { _, _, _, _, _, _ in },
            nil,
            nil,
            nil,
            0,
            &audioQueue
        )
        
        if queueStatus != noErr {
            let errorMsg = "Failed to create audio queue: \(queueStatus)"
            logger.log(errorMsg, level: .error)
            errorHandler(errorMsg)
            return
        }
        
        // Enable level metering
        var enableMetering: UInt32 = 1
        queueStatus = AudioQueueSetProperty(
            audioQueue!,
            kAudioQueueProperty_EnableLevelMetering,
            &enableMetering,
            UInt32(MemoryLayout<UInt32>.size)
        )
        
        if queueStatus != noErr {
            let errorMsg = "Failed to enable level metering: \(queueStatus)"
            logger.log(errorMsg, level: .error)
            errorHandler(errorMsg)
            return
        }
        
        // Set the input device to our selected microphone
        // Convert our UInt32 ID to AudioDeviceID
        var audioDeviceID = AudioDeviceID(deviceID)
        
        // Try a different approach - using Core Audio to set the default input device first
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        // Try to set the default input device
        let defaultStatus = AudioObjectSetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            UInt32(MemoryLayout<AudioDeviceID>.size),
            &audioDeviceID
        )
        
        if defaultStatus != noErr {
            logger.log("Warning: Could not set default input device, status: \(defaultStatus)", level: .warning)
        } else {
            logger.log("Successfully set default input device to ID: \(audioDeviceID)", level: .info)
        }
        
        // Now try to set the device on the queue
        queueStatus = AudioQueueSetProperty(
            audioQueue!,
            kAudioQueueProperty_CurrentDevice,
            &audioDeviceID,
            propSize
        )
        
        if queueStatus != noErr {
            // Error code -66683 is common and doesn't affect functionality
            // since we already set the default input device
            if queueStatus == -66683 {
                logger.log("Note: Using system default device for audio queue (code: \(queueStatus))", level: .warning)
            } else {
                let errorMsg = "Failed to set audio queue device ID: \(queueStatus)"
                logger.log(errorMsg, level: .error)
                errorHandler(errorMsg)
            }
            
            // Continue with the default device regardless of error type
            logger.log("Continuing with default audio device", level: .warning)
        }
        
        // Start the queue
        queueStatus = AudioQueueStart(audioQueue!, nil)
        if queueStatus != noErr {
            let errorMsg = "Failed to start audio queue: \(queueStatus)"
            logger.log(errorMsg, level: .error)
            errorHandler(errorMsg)
            return
        }
        
        // Start timer to check audio levels
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self = self, let queue = self.audioQueue else { return }
            
            var level: Float = 0
            var levelSize = UInt32(MemoryLayout<Float>.size)
            
            // Get the current audio level
            let levelStatus = AudioQueueGetProperty(
                queue,
                kAudioQueueProperty_CurrentLevelMeterDB,
                &level,
                &levelSize
            )
            
            if levelStatus == noErr {
                // Convert dB level to a 0-1 scale
                // Typical values are between -60 (quiet) and 0 (loudest)
                let normalizedLevel = max(0, min(1, (level + 60) / 60))
                levelUpdateHandler(normalizedLevel)
            } else {
                self.logger.log("Failed to get audio level: \(levelStatus)", level: .warning)
                // Send error but continue trying
                errorHandler("Unable to read audio levels")
            }
        }
        
        logger.log("Audio monitoring started for device ID: \(deviceID)")
    }
    
    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
        
        if let queue = audioQueue {
            AudioQueueStop(queue, true)
            AudioQueueDispose(queue, true)
            audioQueue = nil
            logger.log("Audio monitoring stopped for device ID: \(deviceID)")
        }
    }
    
    deinit {
        stopMonitoring()
    }
} 