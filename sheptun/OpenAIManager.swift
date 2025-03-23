import Foundation
import AVFoundation

class OpenAIManager {
    static let shared = OpenAIManager()
    
    private let logger = Logger.shared
    private let baseURL = "https://api.openai.com/v1"
    var lastError: String?
    var isRecordingAudio = false
    
    enum TranscriptionModel: String {
        case whisper1 = "whisper-1"
        case gpt4oTranscribe = "gpt-4o"
        case gpt4oMiniTranscribe = "gpt-4o-mini"
    }
    
    enum APIError: Error, LocalizedError {
        case invalidURL
        case invalidResponse
        case requestFailed(statusCode: Int, message: String)
        case audioProcessingError(String)
        case networkConnectivity(String)
        case taskCancelled
        
        var errorDescription: String? {
            switch self {
            case .invalidURL:
                return "Invalid URL"
            case .invalidResponse:
                return "Invalid response from server"
            case .requestFailed(let statusCode, let message):
                return "Request failed with status code \(statusCode): \(message)"
            case .audioProcessingError(let details):
                return "Audio processing error: \(details)"
            case .networkConnectivity(let details):
                return "Network connectivity issue: \(details)"
            case .taskCancelled:
                return "Task was cancelled"
            }
        }
    }
    
    // These are the structures for JSON decoding
    struct ErrorResponse: Decodable {
        struct ErrorDetail: Decodable {
            let message: String
            let type: String?
            let param: String?
            let code: String?
        }
        let error: ErrorDetail
    }
    
    struct TranscriptionResponse: Decodable {
        let text: String
    }
    
    // Function to start recording
    func startRecording(deviceID: String) {
        // Clear any previous errors
        lastError = nil
        
        // Create an instance of the AudioRecorder with the specified device
        let audioRecorder = AudioRecorder.shared
        
        // Log the start of recording with device ID
        logger.log("Starting audio recording with device ID: \(deviceID)", level: .debug)
        
        // Configure and start the recording
        let didStart = audioRecorder.startRecording(microphoneID: deviceID)
        
        if didStart {
            isRecordingAudio = true
            logger.log("Audio recording started successfully", level: .debug)
        } else {
            isRecordingAudio = false
            lastError = "Failed to start recording"
            logger.log("Failed to start audio recording with device ID: \(deviceID)", level: .error)
        }
    }
    
    // Function to stop recording without transcription
    func stopRecording() {
        logger.log("Stopping audio recording (without transcription)", level: .debug)
        
        // Stop the AudioRecorder
        AudioRecorder.shared.stopRecording()
        
        // Update recording state
        isRecordingAudio = false
        
        logger.log("Audio recording stopped", level: .info)
    }
    
    // Function to stop recording and handle transcription
    func stopRecordingAndTranscribe(
        apiKey: String,
        model: TranscriptionModel = .whisper1,
        prompt: String = "",
        language: String = "",
        completion: @escaping (Result<String, APIError>) -> Void
    ) {
        // Implementation details omitted
    }
    
    // Function to stop transcription
    func stopTranscription() {
        // Implementation details omitted
    }
    
    // Test if the API key is valid
    func testAPIKey(apiKey: String) async -> Bool {
        guard let url = URL(string: "\(baseURL)/models") else {
            logger.log("Invalid URL for API key test", level: .error)
            return false
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            
            if let httpResponse = response as? HTTPURLResponse {
                return httpResponse.statusCode == 200
            }
            return false
        } catch {
            logger.log("Error testing API key: \(error.localizedDescription)", level: .error)
            return false
        }
    }
    
    // Transcribe an audio file using the OpenAI API
    func transcribeAudioFile(audioFileURL: URL, 
                             apiKey: String,
                             model: TranscriptionModel = .whisper1,
                             prompt: String = "",
                             language: String = "") async -> Result<String, APIError> {
        // Implementation details omitted
        return .failure(.audioProcessingError("Method implementation needed"))
    }

    func createWavData(fromPCMData pcmData: Data, format: AVAudioFormat) -> Data? {
        guard pcmData.count > 0 else {
            logger.log("No PCM data provided to create WAV file", level: .error)
            return nil
        }
        
        logger.log("Creating WAV data from PCM data of size: \(pcmData.count) bytes", level: .debug)
        
        // Get audio format parameters
        let sampleRate = UInt32(format.sampleRate)
        let numChannels = UInt16(format.channelCount)
        let bitsPerSample: UInt16 = 16 // We're using Int16 samples (2 bytes)
        
        // Log WAV creation parameters
        logger.log("WAV parameters - Sample rate: \(sampleRate)Hz, Channels: \(numChannels), Bits per sample: \(bitsPerSample)", level: .debug)
        
        // Create WAV header
        var header = Data()
        
        // RIFF header
        header.append("RIFF".data(using: .ascii)!) // ChunkID (4 bytes)
        let fileSize = UInt32(pcmData.count + 36) // File size (4 bytes) - add 36 for header size minus 8 bytes
        header.append(withUnsafeBytes(of: fileSize.littleEndian) { Data($0) })
        header.append("WAVE".data(using: .ascii)!) // Format (4 bytes)
        
        // fmt subchunk
        header.append("fmt ".data(using: .ascii)!) // Subchunk1ID (4 bytes)
        let subchunk1Size: UInt32 = 16 // PCM format (4 bytes)
        header.append(withUnsafeBytes(of: subchunk1Size.littleEndian) { Data($0) })
        let audioFormat: UInt16 = 1 // PCM = 1 (2 bytes)
        header.append(withUnsafeBytes(of: audioFormat.littleEndian) { Data($0) })
        header.append(withUnsafeBytes(of: numChannels.littleEndian) { Data($0) }) // NumChannels (2 bytes)
        header.append(withUnsafeBytes(of: sampleRate.littleEndian) { Data($0) }) // SampleRate (4 bytes)
        
        // Calculate byte rate and block align
        let byteRate = UInt32(sampleRate * UInt32(numChannels) * UInt32(bitsPerSample) / 8)
        let blockAlign = UInt16(numChannels * bitsPerSample / 8)
        
        header.append(withUnsafeBytes(of: byteRate.littleEndian) { Data($0) }) // ByteRate (4 bytes)
        header.append(withUnsafeBytes(of: blockAlign.littleEndian) { Data($0) }) // BlockAlign (2 bytes)
        header.append(withUnsafeBytes(of: bitsPerSample.littleEndian) { Data($0) }) // BitsPerSample (2 bytes)
        
        // data subchunk
        header.append("data".data(using: .ascii)!) // Subchunk2ID (4 bytes)
        let subchunk2Size = UInt32(pcmData.count) // Subchunk2Size (4 bytes) - size of actual audio data
        header.append(withUnsafeBytes(of: subchunk2Size.littleEndian) { Data($0) })
        
        // Create the final WAV data by combining the header and PCM data
        var wavData = Data()
        wavData.append(header)
        wavData.append(pcmData)
        
        logger.log("WAV file created successfully with total size: \(wavData.count) bytes (Header: \(header.count) bytes, PCM: \(pcmData.count) bytes)", level: .debug)
        
        return wavData
    } 
} 