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
        case gpt4oTranscribe = "gpt-4o-transcribe"
        case gpt4oMiniTranscribe = "gpt-4o-mini-transcribe"
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
                             model: TranscriptionModel = .gpt4oTranscribe,
                             prompt: String = "",
                             language: String = "en") async -> Result<String, APIError> {
        // Check if there's an M4A file which contains the full recording
        let m4aURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("temp_recording.m4a")
        
        // Use the M4A file if it exists and is larger than the input file
        let fileToUse: URL
        if FileManager.default.fileExists(atPath: m4aURL.path),
           let m4aAttributes = try? FileManager.default.attributesOfItem(atPath: m4aURL.path),
           let m4aSize = m4aAttributes[.size] as? Int,
           let wavAttributes = try? FileManager.default.attributesOfItem(atPath: audioFileURL.path),
           let wavSize = wavAttributes[.size] as? Int,
           m4aSize > wavSize {
            
            logger.log("Using temp_recording.m4a file (\(m4aSize) bytes) instead of \(audioFileURL.lastPathComponent) (\(wavSize) bytes)", level: .info)
            fileToUse = m4aURL
        } else {
            logger.log("Using provided WAV file: \(audioFileURL.path)", level: .info)
            fileToUse = audioFileURL
        }
        
        logger.log("Starting transcription with model: \(model.rawValue) from file: \(fileToUse.path)", level: .info)
        
        // Use the audio/transcriptions endpoint for all models
        let endpoint = "\(baseURL)/audio/transcriptions"
        
        guard let url = URL(string: endpoint) else {
            logger.log("Invalid URL for transcription API: \(endpoint)", level: .error)
            return .failure(.invalidURL)
        }
        
        let startTime = Date()
        
        do {
            // Add the audio file
            let audioData = try Data(contentsOf: fileToUse)
            let filename = fileToUse.lastPathComponent
            
            // Set up multipart form data for all models
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            
            let boundary = "Boundary-\(UUID().uuidString)"
            request.addValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
            
            var body = Data()
            
            // Add model parameter
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"model\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(model.rawValue)\r\n".data(using: .utf8)!)
            
            // Add prompt parameter if non-empty
            if !prompt.isEmpty {
                body.append("--\(boundary)\r\n".data(using: .utf8)!)
                body.append("Content-Disposition: form-data; name=\"prompt\"\r\n\r\n".data(using: .utf8)!)
                body.append("\(prompt)\r\n".data(using: .utf8)!)
            }
            
            // Add language parameter (default to "en" if not specified)
            let languageToUse = language.isEmpty ? "en" : language
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"language\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(languageToUse)\r\n".data(using: .utf8)!)
            
            // Add temperature parameter (default 0.3)
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"temperature\"\r\n\r\n".data(using: .utf8)!)
            body.append("0.3\r\n".data(using: .utf8)!)
            
            // Add response_format parameter
            let responseFormat = (model == .whisper1) ? "json" : "text"
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"response_format\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(responseFormat)\r\n".data(using: .utf8)!)
            
            // Add the audio file data
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
            
            // Set proper content type based on file extension
            let contentType = fileToUse.pathExtension.lowercased() == "m4a" ? "audio/m4a" : "audio/wav"
            body.append("Content-Type: \(contentType)\r\n\r\n".data(using: .utf8)!)
            body.append(audioData)
            body.append("\r\n".data(using: .utf8)!)
            
            // End the request
            body.append("--\(boundary)--\r\n".data(using: .utf8)!)
            
            // Set the request body
            request.httpBody = body
            
            // Log the request details
            logger.log("Sending API request to: \(endpoint)", level: .debug)
            logger.log("Request headers: \(request.allHTTPHeaderFields ?? [:])", level: .debug)
            logger.log("Request parameters: model=\(model.rawValue), language=\(languageToUse), temperature=0.3, response_format=\(responseFormat)", level: .debug)
            logger.log("Audio file size: \(audioData.count) bytes", level: .debug)
            
            // Make the request
            let (data, response) = try await URLSession.shared.data(for: request)
            
            // Calculate response time
            let responseTime = Date().timeIntervalSince(startTime)
            logger.log("OpenAI API responded in \(String(format: "%.2f", responseTime)) seconds", level: .info)
            
            // Check the response status code
            guard let httpResponse = response as? HTTPURLResponse else {
                logger.log("Invalid response from API", level: .error)
                return .failure(.invalidResponse)
            }
            
            // Log the response
            if let responseString = String(data: data, encoding: .utf8) {
                logger.log("API response (status \(httpResponse.statusCode)): \(responseString)", level: .debug)
            }
            
            if httpResponse.statusCode != 200 {
                // Try to parse error details from the response
                let errorMessage = try? parseErrorMessage(from: data) ?? "Unknown error"
                logger.log("API error (status \(httpResponse.statusCode)): \(errorMessage ?? "Unknown error")", level: .error)
                return .failure(.requestFailed(statusCode: httpResponse.statusCode, message: errorMessage ?? "Unknown error"))
            }
            
            // Parse the response based on response format
            if responseFormat == "json" {
                if let responseObject = try? JSONDecoder().decode(TranscriptionResponse.self, from: data) {
                    logger.log("Transcription successful, received \(responseObject.text.count) characters", level: .info)
                    return .success(responseObject.text)
                } else {
                    logger.log("Failed to decode JSON response from API", level: .error)
                    if let responseString = String(data: data, encoding: .utf8) {
                        logger.log("Raw response: \(responseString)", level: .debug)
                    }
                    return .failure(.invalidResponse)
                }
            } else {
                // For text response format
                if let text = String(data: data, encoding: .utf8) {
                    logger.log("Transcription successful, received \(text.count) characters", level: .info)
                    return .success(text)
                } else {
                    logger.log("Failed to decode text response from API", level: .error)
                    return .failure(.invalidResponse)
                }
            }
        } catch {
            logger.log("Error during transcription: \(error.localizedDescription)", level: .error)
            if let nsError = error as NSError? {
                if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled {
                    return .failure(.taskCancelled)
                } else if nsError.domain == NSURLErrorDomain && 
                          (nsError.code == NSURLErrorNotConnectedToInternet || 
                           nsError.code == NSURLErrorNetworkConnectionLost) {
                    return .failure(.networkConnectivity(nsError.localizedDescription))
                }
            }
            return .failure(.audioProcessingError(error.localizedDescription))
        }
    }
    
    // Helper function to parse error messages from OpenAI API responses
    private func parseErrorMessage(from data: Data) throws -> String? {
        if let jsonObject = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let error = jsonObject["error"] as? [String: Any],
           let message = error["message"] as? String {
            return message
        } else if let errorString = String(data: data, encoding: .utf8) {
            return errorString
        } else {
            return nil
        }
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