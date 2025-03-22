import Foundation

class OpenAIManager {
    static let shared = OpenAIManager()
    private let logger = Logger.shared
    private let baseURL = "https://api.openai.com/v1"
    
    private init() {
        logger.log("OpenAIManager initialized", level: .info)
    }
    
    enum APIError: Error, LocalizedError {
        case invalidURL
        case invalidResponse
        case invalidAPIKey
        case requestFailed(statusCode: Int, message: String)
        case networkConnectivity(String)
        case websocketError(String)
        
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
            case .websocketError(let message):
                return "WebSocket error: \(message)"
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
    
    // MARK: - Live Audio Transcription
    
    enum TranscriptionModel: String, Codable {
        case whisper1 = "whisper-1"
        case gpt4oTranscribe = "gpt-4o-transcribe"
        case gpt4oMiniTranscribe = "gpt-4o-mini-transcribe"
    }
    
    enum NoiseReductionType: String, Codable {
        case nearField = "near_field"
        case farField = "far_field"
    }
    
    struct TranscriptionResult: Codable {
        let text: String
        let isFinal: Bool
    }
    
    struct TranscriptionSessionConfig: Codable {
        let type: String = "transcription_session.update"
        let inputAudioFormat: String = "pcm16"
        let inputAudioTranscription: TranscriptionConfig
        let turnDetection: TurnDetection?
        let inputAudioNoiseReduction: NoiseReduction
        let include: [String]
        
        enum CodingKeys: String, CodingKey {
            case type
            case inputAudioFormat = "input_audio_format"
            case inputAudioTranscription = "input_audio_transcription"
            case turnDetection = "turn_detection"
            case inputAudioNoiseReduction = "input_audio_noise_reduction"
            case include
        }
    }
    
    struct TranscriptionConfig: Codable {
        let model: String
        let prompt: String
        let language: String
    }
    
    struct TurnDetection: Codable {
        let type: String = "server_vad"
        let threshold: Float
        let prefixPaddingMs: Int
        let silenceDurationMs: Int
        
        enum CodingKeys: String, CodingKey {
            case type
            case threshold
            case prefixPaddingMs = "prefix_padding_ms"
            case silenceDurationMs = "silence_duration_ms"
        }
    }
    
    struct NoiseReduction: Codable {
        let type: String
        
        init(type: NoiseReductionType) {
            self.type = type.rawValue
        }
    }
    
    struct AudioBufferAppend: Codable {
        let type: String = "input_audio_buffer.append"
        let audio: String
    }
    
    typealias TranscriptionUpdateHandler = (Result<TranscriptionResult, APIError>) -> Void
    
    private var webSocketTask: URLSessionWebSocketTask?
    private var updateHandler: TranscriptionUpdateHandler?
    
    func startLiveTranscription(apiKey: String, model: TranscriptionModel = .gpt4oTranscribe, prompt: String = "", language: String = "", 
                               noiseReduction: NoiseReductionType = .nearField, 
                               vadThreshold: Float = 0.5, 
                               prefixPaddingMs: Int = 300, 
                               silenceDurationMs: Int = 500,
                               updateHandler: @escaping TranscriptionUpdateHandler) {
        
        self.updateHandler = updateHandler
        
        logger.log("Starting live transcription with model: \(model.rawValue)", level: .info)
        
        guard let url = URL(string: "wss://api.openai.com/v1/realtime?intent=transcription") else {
            updateHandler(.failure(.invalidURL))
            return
        }
        
        let session = URLSession(configuration: .default)
        webSocketTask = session.webSocketTask(with: url)
        
        // Add authentication header
        var request = URLRequest(url: url)
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        webSocketTask = session.webSocketTask(with: request)
        webSocketTask?.resume()
        
        // Configure the WebSocket connection
        let transcriptionConfig = TranscriptionConfig(
            model: model.rawValue,
            prompt: prompt,
            language: language
        )
        
        let turnDetection = TurnDetection(
            threshold: vadThreshold,
            prefixPaddingMs: prefixPaddingMs,
            silenceDurationMs: silenceDurationMs
        )
        
        let noiseReductionConfig = NoiseReduction(type: noiseReduction)
        
        let sessionConfig = TranscriptionSessionConfig(
            inputAudioTranscription: transcriptionConfig,
            turnDetection: turnDetection,
            inputAudioNoiseReduction: noiseReductionConfig,
            include: ["item.input_audio_transcription.logprobs"]
        )
        
        // Send initial configuration
        do {
            let configData = try JSONEncoder().encode(sessionConfig)
            if let configString = String(data: configData, encoding: .utf8) {
                let message = URLSessionWebSocketTask.Message.string(configString)
                webSocketTask?.send(message) { error in
                    if let error = error {
                        self.logger.log("Failed to send configuration: \(error)", level: .error)
                        self.updateHandler?(.failure(.websocketError(error.localizedDescription)))
                    } else {
                        self.logger.log("Configuration sent successfully", level: .debug)
                        self.receiveMessage()
                    }
                }
            }
        } catch {
            logger.log("Failed to encode configuration: \(error)", level: .error)
            updateHandler(.failure(.websocketError(error.localizedDescription)))
        }
    }
    
    func sendAudioData(_ audioData: Data) {
        guard let webSocketTask = webSocketTask else {
            logger.log("WebSocket not initialized", level: .error)
            updateHandler?(.failure(.websocketError("WebSocket not initialized")))
            return
        }
        
        let base64Audio = audioData.base64EncodedString()
        
        let audioBuffer = AudioBufferAppend(audio: base64Audio)
        
        do {
            let data = try JSONEncoder().encode(audioBuffer)
            if let messageString = String(data: data, encoding: .utf8) {
                let message = URLSessionWebSocketTask.Message.string(messageString)
                webSocketTask.send(message) { error in
                    if let error = error {
                        self.logger.log("Failed to send audio data: \(error)", level: .error)
                        self.updateHandler?(.failure(.websocketError(error.localizedDescription)))
                    }
                }
            }
        } catch {
            logger.log("Failed to encode audio data: \(error)", level: .error)
            updateHandler?(.failure(.websocketError(error.localizedDescription)))
        }
    }
    
    // MARK: - WebSocket Response Structures
    
    struct WebSocketResponse: Codable {
        let type: String
        let text: String?
        let isFinal: Bool?
        let item: TranscriptionItem?
        let error: ErrorDetail?
    }
    
    struct TranscriptionItem: Codable {
        let id: String
        let inputAudioTranscription: TranscriptionData?
        
        enum CodingKeys: String, CodingKey {
            case id
            case inputAudioTranscription = "input_audio_transcription"
        }
    }
    
    struct TranscriptionData: Codable {
        let text: String
    }
    
    private func receiveMessage() {
        webSocketTask?.receive { [weak self] result in
            guard let self = self else { return }
            
            switch result {
            case .success(let message):
                switch message {
                case .string(let text):
                    self.logger.log("Received WebSocket message", level: .debug)
                    
                    do {
                        // Try to parse the message as JSON
                        if let data = text.data(using: .utf8),
                           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                            
                            // Extract message type
                            if let type = json["type"] as? String {
                                self.logger.log("Message type: \(type)", level: .debug)
                                
                                // Handle different message types
                                switch type {
                                case "transcription.partial":
                                    if let item = json["item"] as? [String: Any],
                                       let inputTranscription = item["input_audio_transcription"] as? [String: Any],
                                       let text = inputTranscription["text"] as? String {
                                        
                                        let result = TranscriptionResult(text: text, isFinal: false)
                                        self.updateHandler?(.success(result))
                                    }
                                    
                                case "transcription.complete":
                                    if let item = json["item"] as? [String: Any],
                                       let inputTranscription = item["input_audio_transcription"] as? [String: Any],
                                       let text = inputTranscription["text"] as? String {
                                        
                                        let result = TranscriptionResult(text: text, isFinal: true)
                                        self.updateHandler?(.success(result))
                                    }
                                    
                                case "error":
                                    if let error = json["error"] as? [String: Any],
                                       let message = error["message"] as? String {
                                        self.logger.log("WebSocket error: \(message)", level: .error)
                                        self.updateHandler?(.failure(.websocketError(message)))
                                    }
                                    
                                default:
                                    self.logger.log("Unhandled message type: \(type)", level: .warning)
                                }
                            }
                        }
                    } catch {
                        self.logger.log("Failed to parse WebSocket message: \(error)", level: .error)
                    }
                    
                case .data(let data):
                    self.logger.log("Received binary message of size: \(data.count)", level: .debug)
                @unknown default:
                    self.logger.log("Received unsupported message type", level: .warning)
                }
                
                // Continue receiving messages
                self.receiveMessage()
                
            case .failure(let error):
                self.logger.log("WebSocket receive error: \(error)", level: .error)
                self.updateHandler?(.failure(.websocketError(error.localizedDescription)))
            }
        }
    }
    
    func stopLiveTranscription() {
        logger.log("Stopping live transcription", level: .info)
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        updateHandler = nil
    }
    
    // MARK: - Ephemeral Token for WebSocket

    struct EphemeralTokenResponse: Codable {
        let clientSecret: String
        
        enum CodingKeys: String, CodingKey {
            case clientSecret = "client_secret"
        }
    }
    
    func getEphemeralToken(apiKey: String) async -> Result<String, APIError> {
        logger.log("Getting ephemeral token for WebSocket authentication", level: .info)
        
        guard let url = URL(string: "\(baseURL)/realtime/transcription_sessions") else {
            logger.log("Invalid URL for ephemeral token endpoint", level: .error)
            return .failure(.invalidURL)
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        do {
            logger.log("Sending request for ephemeral token", level: .debug)
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                logger.log("Invalid response type", level: .error)
                return .failure(.invalidResponse)
            }
            
            logger.log("HTTP status code: \(httpResponse.statusCode)", level: .debug)
            
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
            
            do {
                let tokenResponse = try JSONDecoder().decode(EphemeralTokenResponse.self, from: data)
                logger.log("Successfully obtained ephemeral token", level: .info)
                return .success(tokenResponse.clientSecret)
            } catch {
                logger.log("Failed to decode token response: \(error)", level: .error)
                return .failure(.invalidResponse)
            }
            
        } catch {
            logger.log("Network request failed: \(error)", level: .error)
            return .failure(.networkConnectivity(error.localizedDescription))
        }
    }
    
    func startLiveTranscriptionWithEphemeralToken(apiKey: String, model: TranscriptionModel = .gpt4oTranscribe, prompt: String = "", language: String = "", 
                                                 noiseReduction: NoiseReductionType = .nearField,
                                                 vadThreshold: Float = 0.5,
                                                 prefixPaddingMs: Int = 300,
                                                 silenceDurationMs: Int = 500,
                                                 updateHandler: @escaping TranscriptionUpdateHandler) async {
        
        // First get an ephemeral token
        let tokenResult = await getEphemeralToken(apiKey: apiKey)
        
        switch tokenResult {
        case .success(let token):
            // Connect with the ephemeral token
            logger.log("Using ephemeral token for WebSocket connection", level: .debug)
            guard let url = URL(string: "wss://api.openai.com/v1/realtime?intent=transcription&client_secret=\(token)") else {
                updateHandler(.failure(.invalidURL))
                return
            }
            
            self.updateHandler = updateHandler
            
            let session = URLSession(configuration: .default)
            webSocketTask = session.webSocketTask(with: url)
            webSocketTask?.resume()
            
            // Configure the WebSocket connection (same as before)
            let transcriptionConfig = TranscriptionConfig(
                model: model.rawValue,
                prompt: prompt,
                language: language
            )
            
            let turnDetection = TurnDetection(
                threshold: vadThreshold,
                prefixPaddingMs: prefixPaddingMs,
                silenceDurationMs: silenceDurationMs
            )
            
            let noiseReductionConfig = NoiseReduction(type: noiseReduction)
            
            let sessionConfig = TranscriptionSessionConfig(
                inputAudioTranscription: transcriptionConfig,
                turnDetection: turnDetection,
                inputAudioNoiseReduction: noiseReductionConfig,
                include: ["item.input_audio_transcription.logprobs"]
            )
            
            // Send initial configuration
            do {
                let configData = try JSONEncoder().encode(sessionConfig)
                if let configString = String(data: configData, encoding: .utf8) {
                    let message = URLSessionWebSocketTask.Message.string(configString)
                    webSocketTask?.send(message) { error in
                        if let error = error {
                            self.logger.log("Failed to send configuration: \(error)", level: .error)
                            self.updateHandler?(.failure(.websocketError(error.localizedDescription)))
                        } else {
                            self.logger.log("Configuration sent successfully", level: .debug)
                            self.receiveMessage()
                        }
                    }
                }
            } catch {
                logger.log("Failed to encode configuration: \(error)", level: .error)
                updateHandler(.failure(.websocketError(error.localizedDescription)))
            }
            
        case .failure(let error):
            logger.log("Failed to get ephemeral token: \(error)", level: .error)
            updateHandler(.failure(error))
        }
    }
} 