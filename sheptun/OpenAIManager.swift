import Foundation

class OpenAIManager {
    static let shared = OpenAIManager()
    private let logger = Logger.shared
    private let baseURL = "https://api.openai.com/v1"
    
    // Status properties
    var isConnected = false
    var messagesSent = 0
    var messagesReceived = 0
    var isRecordingAudio = false
    var lastError: String? = nil
    var transcriptionText = ""
    var transcriptionCallback: ((String, Bool) -> Void)? = nil
    
    // Settings manager
    private let settingsManager = SettingsManager.shared
    
    // Task management
    private var recordingTask: Task<Void, Never>?
    private var transcriptionTask: Task<Void, Never>?
    
    private init() {
        logger.log("OpenAIManager initialized", level: .info)
    }
    
    enum APIError: Error, LocalizedError {
        case invalidURL
        case invalidResponse
        case invalidAPIKey
        case requestFailed(statusCode: Int, message: String)
        case networkConnectivity(String)
        case audioProcessingError(String)
        case recordingNotStarted
        case taskCancelled
        
        var errorDescription: String? {
            switch self {
            case .invalidURL:
                return "Invalid URL"
            case .invalidResponse:
                return "Invalid response from server"
            case .invalidAPIKey:
                return "Invalid API key"
            case let .requestFailed(statusCode, message):
                return "Request failed (Status: \(statusCode)): \(message)"
            case .networkConnectivity(let message):
                return "Network connectivity issue: \(message)"
            case .audioProcessingError(let message):
                return "Audio processing error: \(message)"
            case .recordingNotStarted:
                return "Recording not started or failed to initialize"
            case .taskCancelled:
                return "Operation was cancelled"
            }
        }
    }
    
    struct ErrorResponse: Codable {
        let error: ErrorDetail
    }
    
    struct ErrorDetail: Codable {
        let message: String
        let type: String
    }
    
    func testAPIKey(apiKey: String) async -> Result<Void, APIError> {
        logger.log("testAPIKey() method started in OpenAIManager", level: .debug)
        logger.log("Testing API key by fetching models list", level: .info)
        
        // Basic validation of API key format
        if apiKey.isEmpty {
            logger.log("API key is empty", level: .error)
            return .failure(.invalidAPIKey)
        }
        
        // OpenAI API keys typically start with "sk-" and are about 51 characters long
        if !apiKey.hasPrefix("sk-") || apiKey.count < 20 {
            logger.log("API key format appears invalid", level: .warning)
            // Continue anyway as OpenAI might change their format
        }
        
        guard let url = URL(string: "\(baseURL)/models") else {
            logger.log("Invalid URL for models endpoint", level: .error)
            return .failure(.invalidURL)
        }
        
        logger.log("Creating HTTP request to URL: \(url.absoluteString)", level: .debug)
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        
        do {
            logger.log("About to send HTTP request to OpenAI API", level: .debug)
            let (data, response) = try await URLSession.shared.data(for: request)
            logger.log("Received response from OpenAI API", level: .debug)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                logger.log("Invalid response type", level: .error)
                return .failure(.invalidResponse)
            }
            
            logger.log("HTTP status code: \(httpResponse.statusCode)", level: .debug)
            
            // Check for HTTP status codes
            if httpResponse.statusCode == 401 {
                logger.log("API key authentication failed (401)", level: .error)
                return .failure(.invalidAPIKey)
            }
            
            if httpResponse.statusCode != 200 {
                // Try to parse error message from response
                if let errorResponse = try? JSONDecoder().decode(ErrorResponse.self, from: data) {
                    logger.log("API error: \(errorResponse.error.message)", level: .error)
                    return .failure(.requestFailed(statusCode: httpResponse.statusCode, message: errorResponse.error.message))
                } else {
                    logger.log("Request failed with status code: \(httpResponse.statusCode)", level: .error)
                    return .failure(.requestFailed(statusCode: httpResponse.statusCode, message: "Unknown error"))
                }
            }
            
            // If we got here, the API key is valid (we got a 200 response)
            logger.log("API key validated successfully", level: .info)
            return .success(())
            
        } catch {
            logger.log("Network request failed: \(error)", level: .error)
            logger.log("Error details: \(error.localizedDescription)", level: .debug)
            
            // Detect network connectivity issues
            let nsError = error as NSError
            if nsError.domain == NSURLErrorDomain {
                switch nsError.code {
                case NSURLErrorNotConnectedToInternet, 
                     NSURLErrorNetworkConnectionLost,
                     NSURLErrorCannotFindHost,
                     NSURLErrorCannotConnectToHost,
                     NSURLErrorDNSLookupFailed,
                     NSURLErrorTimedOut:
                    return .failure(.networkConnectivity(error.localizedDescription))
                default:
                    break
                }
            }
            
            return .failure(.requestFailed(statusCode: 0, message: error.localizedDescription))
        }
    }
    
    // MARK: - Audio Transcription
    
    enum TranscriptionModel: String, Codable {
        case whisper1 = "whisper-1"
        case gpt4oTranscribe = "gpt-4o-transcribe"
        case gpt4oMiniTranscribe = "gpt-4o-mini-transcribe"
    }
    
    struct TranscriptionResponse: Codable {
        let text: String
    }
    
    private var audioRecorder: AudioRecorder?
    private var recordedAudioURL: URL?
    private var audioTimer: Timer?
    
    // Start recording audio for transcription
    func startRecording(deviceID: String) {
        // Cancel any existing recording task
        recordingTask?.cancel()
        
        recordingTask = Task { [weak self] in
            guard let self = self else { return }
            
            guard !self.isRecordingAudio else {
                self.logger.log("Already recording audio", level: .warning)
                return
            }
            
            self.logger.log("Starting audio recording for transcription with device ID: \(deviceID)", level: .info)
            
            // Reset error state before recording
            self.lastError = nil
            
            // Get the audio recorder
            let audioRecorder = AudioRecorder.shared
            
            // Start recording on the main thread
            await MainActor.run {
                audioRecorder.startRecording()
                self.isRecordingAudio = true
                self.transcriptionText = ""
            }
        }
    }
    
    // Stop recording and transcribe the audio
    func stopRecordingAndTranscribe(apiKey: String, 
                                   model: TranscriptionModel = .whisper1,
                                   prompt: String = "",
                                   language: String = "",
                                   completion: @escaping (Result<String, APIError>) -> Void) {
        
        // Cancel any existing transcription task
        transcriptionTask?.cancel()
        
        transcriptionTask = Task { [weak self] in
            guard let self = self else {
                completion(.failure(.audioProcessingError("OpenAIManager instance no longer available")))
                return
            }
            
            guard self.isRecordingAudio else {
                self.logger.log("Not currently recording audio", level: .warning)
                completion(.failure(.recordingNotStarted))
                return
            }
            
            self.logger.log("Stopping recording and starting transcription with model: \(model.rawValue)", level: .info)
            
            let audioRecorder = AudioRecorder.shared
            
            // Get the audio buffer before stopping the recording
            let audioData = audioRecorder.getLatestAudioBuffer()
            
            // Now stop the recording
            await MainActor.run {
                audioRecorder.stopRecording()
                self.isRecordingAudio = false
            }
            
            guard let audioData = audioData, !audioData.isEmpty else {
                self.logger.log("No audio data available", level: .error)
                completion(.failure(.audioProcessingError("No audio data available or recording was too short")))
                return
            }
            
            let tempDir = NSTemporaryDirectory()
            let tempURL = URL(fileURLWithPath: tempDir).appendingPathComponent("recording.wav")
            
            do {
                try audioData.write(to: tempURL)
                self.logger.log("Saved audio data to temporary file: \(tempURL.path)", level: .debug)
                
                // Start transcription
                do {
                    let result = await self.transcribeAudioFile(
                        audioFileURL: tempURL,
                        apiKey: apiKey,
                        model: model,
                        prompt: prompt,
                        language: language
                    )
                    
                    if Task.isCancelled {
                        completion(.failure(.taskCancelled))
                        return
                    }
                    
                    // Pass result back to the completion handler
                    switch result {
                    case .success(let transcription):
                        self.transcriptionText = transcription
                        self.transcriptionCallback?(transcription, true)
                        completion(.success(transcription))
                    case .failure(let error):
                        self.lastError = error.localizedDescription
                        completion(.failure(error))
                    }
                    
                    // Clean up the temporary file
                    try? FileManager.default.removeItem(at: tempURL)
                } catch {
                    self.logger.log("Transcription process error: \(error)", level: .error)
                    completion(.failure(.audioProcessingError("Transcription process error: \(error.localizedDescription)")))
                }
                
            } catch {
                self.logger.log("Failed to save audio data: \(error)", level: .error)
                completion(.failure(.audioProcessingError("Failed to save audio: \(error.localizedDescription)")))
            }
        }
    }
    
    // Transcribe an audio file using the OpenAI API
    func transcribeAudioFile(audioFileURL: URL, 
                             apiKey: String,
                             model: TranscriptionModel = .whisper1,
                             prompt: String = "",
                             language: String = "") async -> Result<String, APIError> {
        
        logger.log("Transcribing audio file: \(audioFileURL.lastPathComponent) with model: \(model.rawValue)", level: .info)
        
        guard let url = URL(string: "\(baseURL)/audio/transcriptions") else {
            logger.log("Invalid URL for transcriptions endpoint", level: .error)
            return .failure(.invalidURL)
        }
        
        // Prepare multipart form request
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        
        let boundary = UUID().uuidString
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        
        var httpBody = Data()
        
        // Add model parameter
        httpBody.append("--\(boundary)\r\n".data(using: .utf8)!)
        httpBody.append("Content-Disposition: form-data; name=\"model\"\r\n\r\n".data(using: .utf8)!)
        httpBody.append("\(model.rawValue)\r\n".data(using: .utf8)!)
        
        // Add prompt parameter if provided
        if !prompt.isEmpty {
            httpBody.append("--\(boundary)\r\n".data(using: .utf8)!)
            httpBody.append("Content-Disposition: form-data; name=\"prompt\"\r\n\r\n".data(using: .utf8)!)
            httpBody.append("\(prompt)\r\n".data(using: .utf8)!)
        }
        
        // Add language parameter if provided
        if !language.isEmpty {
            httpBody.append("--\(boundary)\r\n".data(using: .utf8)!)
            httpBody.append("Content-Disposition: form-data; name=\"language\"\r\n\r\n".data(using: .utf8)!)
            httpBody.append("\(language)\r\n".data(using: .utf8)!)
        }
        
        // Add response format (json)
        httpBody.append("--\(boundary)\r\n".data(using: .utf8)!)
        httpBody.append("Content-Disposition: form-data; name=\"response_format\"\r\n\r\n".data(using: .utf8)!)
        httpBody.append("json\r\n".data(using: .utf8)!)
        
        // Add the audio file
        do {
            let audioData = try Data(contentsOf: audioFileURL)
            
            httpBody.append("--\(boundary)\r\n".data(using: .utf8)!)
            httpBody.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(audioFileURL.lastPathComponent)\"\r\n".data(using: .utf8)!)
            httpBody.append("Content-Type: audio/wav\r\n\r\n".data(using: .utf8)!)
            httpBody.append(audioData)
            httpBody.append("\r\n".data(using: .utf8)!)
        } catch {
            logger.log("Failed to read audio file: \(error)", level: .error)
            return .failure(.audioProcessingError("Failed to read audio file: \(error.localizedDescription)"))
        }
        
        // Final boundary
        httpBody.append("--\(boundary)--\r\n".data(using: .utf8)!)
        
        request.httpBody = httpBody
        
        // Send the request
        do {
            logger.log("Sending transcription request to OpenAI API", level: .debug)
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                logger.log("Invalid response type", level: .error)
                return .failure(.invalidResponse)
            }
            
            logger.log("Transcription API response with status code: \(httpResponse.statusCode)", level: .debug)
            
            if httpResponse.statusCode != 200 {
                // Handle error response
                if let errorResponse = try? JSONDecoder().decode(ErrorResponse.self, from: data) {
                    logger.log("API error: \(errorResponse.error.message)", level: .error)
                    return .failure(.requestFailed(statusCode: httpResponse.statusCode, message: errorResponse.error.message))
                } else {
                    logger.log("Request failed with status code: \(httpResponse.statusCode)", level: .error)
                    if let responseText = String(data: data, encoding: .utf8) {
                        logger.log("Response body: \(responseText)", level: .debug)
                    }
                    return .failure(.requestFailed(statusCode: httpResponse.statusCode, message: "Unknown error"))
                }
            }
            
            // Parse successful response
            do {
                let transcriptionResponse = try JSONDecoder().decode(TranscriptionResponse.self, from: data)
                logger.log("Successfully transcribed audio", level: .info)
                return .success(transcriptionResponse.text)
            } catch {
                logger.log("Failed to decode transcription response: \(error)", level: .error)
                if let responseText = String(data: data, encoding: .utf8) {
                    logger.log("Response body: \(responseText)", level: .debug)
                }
                return .failure(.invalidResponse)
            }
            
        } catch {
            logger.log("Network request failed: \(error)", level: .error)
            
            // Check for task cancellation
            if error is CancellationError {
                return .failure(.taskCancelled)
            }
            
            // Handle network connectivity issues
            let nsError = error as NSError
            if nsError.domain == NSURLErrorDomain {
                switch nsError.code {
                case NSURLErrorNotConnectedToInternet, 
                     NSURLErrorNetworkConnectionLost,
                     NSURLErrorCannotFindHost,
                     NSURLErrorCannotConnectToHost,
                     NSURLErrorDNSLookupFailed,
                     NSURLErrorTimedOut:
                    return .failure(.networkConnectivity(error.localizedDescription))
                default:
                    break
                }
            }
            
            return .failure(.requestFailed(statusCode: 0, message: error.localizedDescription))
        }
    }
    
    // Utility function to extend Data for form data
    private func createFormData(parameters: [String: String], boundary: String, data: Data, mimeType: String, filename: String) -> Data {
        var formData = Data()
        
        // Add the parameters
        for (key, value) in parameters {
            formData.append("--\(boundary)\r\n".data(using: .utf8)!)
            formData.append("Content-Disposition: form-data; name=\"\(key)\"\r\n\r\n".data(using: .utf8)!)
            formData.append("\(value)\r\n".data(using: .utf8)!)
        }
        
        // Add the data
        formData.append("--\(boundary)\r\n".data(using: .utf8)!)
        formData.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        formData.append("Content-Type: \(mimeType)\r\n\r\n".data(using: .utf8)!)
        formData.append(data)
        formData.append("\r\n".data(using: .utf8)!)
        
        // Add the closing boundary
        formData.append("--\(boundary)--\r\n".data(using: .utf8)!)
        
        return formData
    }
    
    // Stop transcription and clean up resources
    func stopTranscription() {
        logger.log("Stopping transcription", level: .info)
        
        // Cancel any ongoing tasks
        recordingTask?.cancel()
        transcriptionTask?.cancel()
        
        if isRecordingAudio {
            let audioRecorder = AudioRecorder.shared
            audioRecorder.stopRecording()
        }
        
        // Clean up resources
        audioTimer?.invalidate()
        audioTimer = nil
        
        isRecordingAudio = false
        transcriptionText = ""
        transcriptionCallback = nil
    }
}

// MARK: - Data Extension for Multipart Form Data
extension Data {
    mutating func append(_ string: String) {
        if let data = string.data(using: .utf8) {
            append(data)
        }
    }
} 