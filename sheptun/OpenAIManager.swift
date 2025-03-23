import Foundation

class OpenAIManager {
    static let shared = OpenAIManager()
    private let logger = Logger.shared
    private let baseURL = "https://api.openai.com/v1"
    
    // Status properties
    var isConnected = false
    var isConnecting = false
    var messagesSent = 0
    var messagesReceived = 0
    var audioChunksSent = 0
    var isRecordingAudio = false
    var lastError: String? = nil
    var transcriptionText = ""
    var transcriptionCallback: ((String, Bool) -> Void)? = nil
    
    // Settings manager
    private let settingsManager = SettingsManager.shared
    
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
        let transcription: TranscriptionConfig
        let turnDetection: TurnDetection?
        let include: [String]
        
        enum CodingKeys: String, CodingKey {
            case type
            case transcription = "input_audio_transcription"
            case turnDetection = "turn_detection"
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
        
        // Add authentication header
        var request = URLRequest(url: url)
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("realtime=v1", forHTTPHeaderField: "openai-beta")
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
        
        let sessionConfig = TranscriptionSessionConfig(
            transcription: transcriptionConfig,
            turnDetection: turnDetection,
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
        guard let webSocketTask = webSocketTask, isConnected else {
            logger.log("WebSocket not initialized or not connected", level: .error)
            updateHandler?(.failure(.websocketError("WebSocket not initialized or not connected")))
            return
        }
        
        let base64Audio = audioData.base64EncodedString()
        
        // Create input_audio_buffer.append message
        let audioAppendDict: [String: Any] = [
            "type": "input_audio_buffer.append",
            "audio": base64Audio,
            "timestamp": Int(Date().timeIntervalSince1970 * 1000) // Add timestamp in milliseconds
        ]
        
        do {
            let data = try JSONSerialization.data(withJSONObject: audioAppendDict)
            if let messageString = String(data: data, encoding: .utf8) {
                let message = URLSessionWebSocketTask.Message.string(messageString)
                webSocketTask.send(message) { [weak self] error in
                    guard let self = self else { return }
                    
                    if let error = error {
                        self.logger.log("Failed to send audio data: \(error)", level: .error)
                        self.updateHandler?(.failure(.websocketError(error.localizedDescription)))
                    } else {
                        self.messagesSent += 1
                        self.audioChunksSent += 1
                        
                        // Log every 10 chunks to avoid excessive logging
                        if self.audioChunksSent % 10 == 0 {
                            self.logger.log("Sent \(self.audioChunksSent) audio chunks", level: .debug)
                        }
                    }
                }
            }
        } catch {
            logger.log("Failed to encode audio data: \(error)", level: .error)
            updateHandler?(.failure(.websocketError(error.localizedDescription)))
        }
    }
    
    // Send input_audio_buffer.commit when VAD is disabled
    func commitAudioBuffer() {
        guard let webSocketTask = webSocketTask, isConnected else {
            logger.log("WebSocket not initialized or not connected", level: .error)
            return
        }
        
        let commitDict: [String: Any] = [
            "type": "input_audio_buffer.commit"
        ]
        
        do {
            let data = try JSONSerialization.data(withJSONObject: commitDict)
            if let messageString = String(data: data, encoding: .utf8) {
                let message = URLSessionWebSocketTask.Message.string(messageString)
                webSocketTask.send(message) { [weak self] error in
                    guard let self = self else { return }
                    
                    if let error = error {
                        self.logger.log("Failed to send audio buffer commit: \(error)", level: .error)
                    } else {
                        self.logger.log("Audio buffer committed manually", level: .info)
                        self.messagesSent += 1
                    }
                }
            }
        } catch {
            logger.log("Failed to encode audio buffer commit: \(error)", level: .error)
        }
    }
    
    // Send input_audio_buffer.clear when needed
    func clearAudioBuffer() {
        guard let webSocketTask = webSocketTask, isConnected else {
            logger.log("WebSocket not initialized or not connected", level: .error)
            return
        }
        
        let clearDict: [String: Any] = [
            "type": "input_audio_buffer.clear"
        ]
        
        do {
            let data = try JSONSerialization.data(withJSONObject: clearDict)
            if let messageString = String(data: data, encoding: .utf8) {
                let message = URLSessionWebSocketTask.Message.string(messageString)
                webSocketTask.send(message) { [weak self] error in
                    guard let self = self else { return }
                    
                    if let error = error {
                        self.logger.log("Failed to clear audio buffer: \(error)", level: .error)
                    } else {
                        self.logger.log("Audio buffer cleared", level: .info)
                        self.messagesSent += 1
                    }
                }
            }
        } catch {
            logger.log("Failed to encode audio buffer clear: \(error)", level: .error)
        }
    }
    
    // Create a response when VAD is disabled
    func createResponse() {
        guard let webSocketTask = webSocketTask, isConnected else {
            logger.log("WebSocket not initialized or not connected", level: .error)
            return
        }
        
        let responseDict: [String: Any] = [
            "type": "response.create"
        ]
        
        do {
            let data = try JSONSerialization.data(withJSONObject: responseDict)
            if let messageString = String(data: data, encoding: .utf8) {
                let message = URLSessionWebSocketTask.Message.string(messageString)
                webSocketTask.send(message) { [weak self] error in
                    guard let self = self else { return }
                    
                    if let error = error {
                        self.logger.log("Failed to create response: \(error)", level: .error)
                    } else {
                        self.logger.log("Response created", level: .info)
                        self.messagesSent += 1
                    }
                }
            }
        } catch {
            logger.log("Failed to encode response creation: \(error)", level: .error)
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
            case inputAudioTranscription = "transcription"
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
                                       let inputTranscription = item["transcription"] as? [String: Any],
                                       let text = inputTranscription["text"] as? String {
                                        self.processTurnWithText(text, isFinal: false)
                                    }
                                    
                                case "transcription.final":
                                    if let item = json["item"] as? [String: Any],
                                       let inputTranscription = item["transcription"] as? [String: Any],
                                       let text = inputTranscription["text"] as? String {
                                        self.processTurnWithText(text, isFinal: true)
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
        let id: String?
        let clientSecret: String?
        let token: TokenInfo?
        
        enum CodingKeys: String, CodingKey {
            case id
            case clientSecret = "client_secret"
            case token
        }
        
        // Nested structure for token info, in case API returns client_secret as a nested object
        struct TokenInfo: Codable {
            let value: String?
            
            // Add any other fields that might be in the token object
            // This is a flexible approach since we don't know the exact structure
            
            private enum CodingKeys: String, CodingKey {
                case value
            }
            
            // Custom init to handle String or object format
            init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                value = try container.decodeIfPresent(String.self, forKey: .value)
            }
        }
        
        // Custom init to handle different response formats
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            
            // Initialize id property
            id = try container.decodeIfPresent(String.self, forKey: .id)
            
            // Try to decode client_secret as a simple string first
            do {
                clientSecret = try container.decodeIfPresent(String.self, forKey: .clientSecret)
                token = nil
            } catch {
                // If that fails, try to decode it as a nested object
                clientSecret = nil
                token = try container.decodeIfPresent(TokenInfo.self, forKey: .clientSecret)
                
                // If neither worked, both will be nil, so the function will handle the error
            }
        }
        
        // Function to get the token regardless of where it's stored
        func getToken() -> String? {
            if let directToken = clientSecret {
                return directToken
            } else if let nestedToken = token?.value {
                return nestedToken
            }
            return nil
        }
    }
    
    func getEphemeralToken(apiKey: String) async -> Result<(String, String?), APIError> {
        logger.log("Getting ephemeral token for WebSocket authentication", level: .info)
        
        guard let url = URL(string: "\(baseURL)/realtime/transcription_sessions") else {
            logger.log("Invalid URL for ephemeral token endpoint", level: .error)
            return .failure(.invalidURL)
        }
        
        logger.log("Making request to \(url.absoluteString)", level: .debug)
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 10.0  // Add explicit timeout
        
        do {
            logger.log("Sending request for ephemeral token", level: .debug)
            
            // Use a dedicated task to track the progress
            let task = Task {
                return try await URLSession.shared.data(for: request)
            }
            
            // Wait for the task with timeout monitoring in debug mode
            let startTime = Date()
            logger.log("Request started at \(startTime)", level: .debug)
            
            let (data, response) = try await task.value
            
            let endTime = Date()
            let timeElapsed = endTime.timeIntervalSince(startTime)
            logger.log("Request completed in \(timeElapsed) seconds", level: .debug)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                logger.log("Invalid response type", level: .error)
                return .failure(.invalidResponse)
            }
            
            logger.log("HTTP status code: \(httpResponse.statusCode)", level: .debug)
            
            // Log the raw response data for debugging
            if let responseString = String(data: data, encoding: .utf8) {
                logger.log("Raw API response: \(responseString)", level: .debug)
            }
            
            // Try to parse as a general JSON object for debugging
            if let jsonObj = try? JSONSerialization.jsonObject(with: data) {
                let jsonDescription = String(describing: jsonObj)
                logger.log("Response as JSON: \(jsonDescription)", level: .debug)
            }
            
            if httpResponse.statusCode != 200 {
                // Try to parse error message from response
                if let errorResponse = try? JSONDecoder().decode(ErrorResponse.self, from: data) {
                    logger.log("API error: \(errorResponse.error.message)", level: .error)
                    return .failure(.requestFailed(statusCode: httpResponse.statusCode, message: errorResponse.error.message))
                } else {
                    logger.log("Request failed with status code: \(httpResponse.statusCode)", level: .error)
                    
                    // Try to extract more detailed error info
                    if let jsonObj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let error = jsonObj["error"] as? [String: Any] {
                        let errorDetails = String(describing: error)
                        logger.log("Error details: \(errorDetails)", level: .error)
                        return .failure(.requestFailed(statusCode: httpResponse.statusCode, message: errorDetails))
                    }
                    
                    return .failure(.requestFailed(statusCode: httpResponse.statusCode, message: "Unknown error"))
                }
            }
            
            // Rest of the method remains the same...
            do {
                let tokenResponse = try JSONDecoder().decode(EphemeralTokenResponse.self, from: data)
                
                if let token = tokenResponse.getToken() {
                    logger.log("Successfully obtained ephemeral token", level: .info)
                    return .success((token, tokenResponse.id))
                } else {
                    logger.log("Token is nil or empty in response", level: .error)
                    return .failure(.invalidResponse)
                }
            } catch {
                logger.log("Failed to decode token response: \(error)", level: .error)
                
                // Fallback: Try to extract the token and session ID manually if structured parsing failed
                if let json = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] {
                    // Try different possible paths to the token
                    let sessionId = json["id"] as? String
                    
                    if let clientSecret = json["client_secret"] as? String {
                        logger.log("Extracted client_secret manually as string", level: .info)
                        return .success((clientSecret, sessionId))
                    } else if let clientSecretDict = json["client_secret"] as? [String: Any],
                              let value = clientSecretDict["value"] as? String {
                        logger.log("Extracted client_secret manually as dictionary", level: .info)
                        return .success((value, sessionId))
                    }
                }
                
                return .failure(.invalidResponse)
            }
            
        } catch {
            logger.log("Network request failed: \(error)", level: .error)
            
            // Provide more detailed error information
            if let urlError = error as? URLError {
                logger.log("URL Error code: \(urlError.code.rawValue), localizedDescription: \(urlError.localizedDescription)", level: .error)
                
                switch urlError.code {
                case .notConnectedToInternet:
                    return .failure(.networkConnectivity("Not connected to internet"))
                case .timedOut:
                    return .failure(.networkConnectivity("Request timed out"))
                case .cannotFindHost, .cannotConnectToHost:
                    return .failure(.networkConnectivity("Cannot connect to OpenAI servers"))
                default:
                    break
                }
            }
            
            return .failure(.networkConnectivity(error.localizedDescription))
        }
    }
    
    // Separate socket connection from audio recording
    func connectToWebSocketOnly(deviceID: String, model: TranscriptionModel = .gpt4oTranscribe) async {
        logger.log("Connecting to WebSocket without starting audio", level: .info)
        
        guard !isConnecting else {
            logger.log("Connection already in progress, ignoring request", level: .warning)
            return
        }
        
        // Get the OpenAI API key from settings
        let apiKey = settingsManager.openAIKey
        guard !apiKey.isEmpty else {
            logger.log("No API key available", level: .error)
            self.lastError = "API key is not set. Please set it in the settings."
            return
        }
        
        // Set as connecting before we start
        self.isConnecting = true
        
        // Reset connection status and counters
        self.isConnected = false
        self.messagesSent = 0
        self.messagesReceived = 0
        self.audioChunksSent = 0
        self.lastError = nil
        
        // Start a task to get the ephemeral token and connect
        Task {
            // Get the ephemeral token
            let tokenResult = await getEphemeralToken(apiKey: apiKey)
            
            switch tokenResult {
            case .success(let (token, sessionId)):
                logger.log("Successfully retrieved ephemeral token, connecting to WebSocket", level: .info)
                
                // Now connect with the token and session ID
                if let sessionId = sessionId {
                    logger.log("Session ID retrieved: \(sessionId)", level: .info)
                    await self.connectToWebSocketInternal(with: token, sessionId: sessionId, deviceID: deviceID, model: model)
                } else {
                    logger.log("No session ID found in response", level: .warning)
                    // Try to connect without session ID as fallback
                    await self.connectToWebSocketInternal(with: token, sessionId: nil, deviceID: deviceID, model: model)
                }
                
            case .failure(let error):
                self.isConnecting = false
                logger.log("Failed to get ephemeral token: \(error)", level: .error)
                self.lastError = "Failed to get token: \(error)"
            }
        }
    }

    private func connectToWebSocketInternal(with token: String, sessionId: String?, deviceID: String, model: TranscriptionModel) async {
        logger.log("Connecting to WebSocket with ephemeral token", level: .info)
        
        guard let url = URL(string: "wss://api.openai.com/v1/realtime?intent=transcription") else {
            logger.log("Invalid WebSocket URL", level: .error)
            self.isConnecting = false
            self.lastError = "Invalid WebSocket URL"
            return
        }
        
        let session = URLSession(configuration: .default)
        
        // Create a request with the proper authorization header
        var request = URLRequest(url: url)
        request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.addValue("realtime=v1", forHTTPHeaderField: "openai-beta")
        request.timeoutInterval = 15.0  // Add a timeout to prevent hanging connections
        
        logger.log("Creating WebSocket task with URL: \(url.absoluteString)", level: .debug)
        
        // Create WebSocket task with the request including auth header
        webSocketTask = session.webSocketTask(with: request)
        
        // Add completion handler for WebSocket task
        webSocketTask?.resume()
        logger.log("WebSocket task resumed", level: .debug)
        
        // Create session configuration with session ID if available
        var sessionDict: [String: Any] = [
            "input_audio_transcription": [
                "model": model.rawValue,
                "prompt": "",
                "language": ""
            ],
            "turn_detection": [
                "type": "server_vad",
                "threshold": 0.5,
                "prefix_padding_ms": 300,
                "silence_duration_ms": 500
            ],
            "include": ["item.input_audio_transcription.logprobs"]
        ]
        
        // Add session ID if available
        if let sessionId = sessionId {
            sessionDict["id"] = sessionId
        }
        
        var configDict: [String: Any] = [
            "type": "transcription_session.update",
            "session": sessionDict
        ]
        
        // Send configuration as JSON
        do {
            let configData = try JSONSerialization.data(withJSONObject: configDict)
            if let configString = String(data: configData, encoding: .utf8) {
                logger.log("Sending WebSocket configuration: \(configString)", level: .debug)
                
                let message = URLSessionWebSocketTask.Message.string(configString)
                webSocketTask?.send(message) { [weak self] error in
                    guard let self = self else { return }
                    
                    if let error = error {
                        self.isConnecting = false
                        self.logger.log("Failed to send configuration: \(error)", level: .error)
                        self.lastError = "Failed to send WebSocket configuration: \(error.localizedDescription)"
                    } else {
                        self.logger.log("Configuration sent successfully", level: .info)
                        self.messagesSent += 1
                        
                        // Listen for messages
                        self.listenForMessages()
                    }
                }
            }
        } catch {
            isConnecting = false
            logger.log("Failed to encode WebSocket configuration: \(error)", level: .error)
            lastError = "Failed to encode configuration: \(error.localizedDescription)"
        }
    }
    
    private func listenForMessages() {
        logger.log("Starting to listen for WebSocket messages", level: .debug)
        
        webSocketTask?.receive { [weak self] result in
            guard let self = self else { return }
            
            switch result {
            case .success(let message):
                self.messagesReceived += 1
                
                switch message {
                case .string(let text):
                    self.logger.log("Received WebSocket message: \(text)", level: .debug)
                    
                    do {
                        if let data = text.data(using: .utf8),
                           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                            
                            if let type = json["type"] as? String {
                                self.logger.log("Message type: \(type)", level: .debug)
                                
                                switch type {
                                case "session.created", "session.updated":
                                    // Session is ready, mark as connected
                                    if !self.isConnected {
                                        self.isConnected = true
                                        self.isConnecting = false
                                        self.logger.log("WebSocket session established", level: .info)
                                    }
                                    
                                case "transcription.partial":
                                    if let item = json["item"] as? [String: Any],
                                       let inputTranscription = item["transcription"] as? [String: Any],
                                       let text = inputTranscription["text"] as? String {
                                        self.processTurnWithText(text, isFinal: false)
                                    }
                                    
                                case "transcription.final":
                                    if let item = json["item"] as? [String: Any],
                                       let inputTranscription = item["transcription"] as? [String: Any],
                                       let text = inputTranscription["text"] as? String {
                                        self.processTurnWithText(text, isFinal: true)
                                    }
                                    
                                case "input_audio_buffer.speech_started":
                                    self.logger.log("Speech started detected", level: .info)
                                    
                                    // You could trigger UI updates here to show that speech is being detected
                                    // For example, show a "Listening..." indicator
                                    
                                case "input_audio_buffer.speech_stopped":
                                    self.logger.log("Speech stopped detected", level: .info)
                                    
                                    // You could update UI to show speech has stopped
                                    // If you are using manual VAD, you might want to call commitAudioBuffer() here
                                    
                                case "input_audio_buffer.committed":
                                    self.logger.log("Audio buffer committed", level: .info)
                                    
                                    // This indicates that the server has accepted and is processing an audio segment
                                    // You could update the UI to show processing is happening
                                    
                                case "response.audio.delta":
                                    // For assistant audio responses, if applicable
                                    self.logger.log("Received audio delta", level: .debug)
                                    
                                case "response.text.delta":
                                    // For assistant text responses, if applicable
                                    if let delta = json["delta"] as? [String: Any],
                                       let text = delta["text"] as? String {
                                        self.logger.log("Text delta: \(text)", level: .debug)
                                        // Handle the text delta if needed
                                    }
                                    
                                case "response.complete":
                                    self.logger.log("Response completed", level: .info)
                                    
                                case "rate_limits.updated":
                                    if let limits = json["rate_limits"] as? [String: Any] {
                                        self.logger.log("Rate limits updated: \(limits)", level: .debug)
                                    }
                                    
                                case "error":
                                    if let error = json["error"] as? [String: Any],
                                       let message = error["message"] as? String {
                                        self.logger.log("WebSocket error: \(message)", level: .error)
                                        self.lastError = "WebSocket error: \(message)"
                                    }
                                    
                                default:
                                    self.logger.log("Unhandled message type: \(type)", level: .debug)
                                }
                            } else {
                                self.logger.log("No type field in message: \(text)", level: .warning)
                            }
                        } else {
                            self.logger.log("Couldn't parse JSON from message: \(text)", level: .warning)
                        }
                    } catch {
                        self.logger.log("Failed to parse WebSocket message: \(error), Text: \(text)", level: .error)
                    }
                    
                case .data(let data):
                    self.logger.log("Received binary message of size: \(data.count)", level: .debug)
                    
                @unknown default:
                    self.logger.log("Received unsupported message type", level: .warning)
                }
                
                // Continue receiving messages if still connected
                if self.webSocketTask != nil {
                    self.listenForMessages()
                } else {
                    self.logger.log("WebSocket task is nil, stopping message listener", level: .warning)
                }
                
            case .failure(let error):
                self.logger.log("WebSocket receive error: \(error)", level: .error)
                self.lastError = "WebSocket error: \(error.localizedDescription)"
                self.isConnected = false
                self.isConnecting = false
                
                // Log network-specific errors 
                if let nsError = error as NSError? {
                    self.logger.log("WebSocket error domain: \(nsError.domain), code: \(nsError.code)", level: .error)
                    
                    // Check for specific URLSession error codes
                    if nsError.domain == NSURLErrorDomain {
                        switch nsError.code {
                        case NSURLErrorNotConnectedToInternet:
                            self.lastError = "Not connected to the internet"
                        case NSURLErrorNetworkConnectionLost:
                            self.lastError = "Network connection lost"
                        case NSURLErrorCannotFindHost, NSURLErrorCannotConnectToHost:
                            self.lastError = "Cannot connect to OpenAI servers"
                        case NSURLErrorTimedOut:
                            self.lastError = "Connection timed out"
                        default:
                            break
                        }
                    }
                }
            }
        }
    }
    
    private func setupAudioMonitoring(deviceID: String) {
        logger.log("Setting up audio monitoring for device ID: \(deviceID)", level: .info)
        
        // Get the audio recorder instance
        let audioRecorder = AudioRecorder.shared
        
        // Start recording with the current device ID
        audioRecorder.startRecording()
        
        // Set up a timer to periodically send audio data
        let timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self = self, self.isConnected else { return }
            
            // Get audio data from the recorder and send it to the WebSocket
            if let audioData = audioRecorder.getLatestAudioBuffer() {
                self.sendAudioData(audioData)
            }
        }
        
        // Store the timer in a property to keep it alive
        self.audioTimer = timer
    }
    
    private var audioTimer: Timer?
    
    func stopTranscription() {
        logger.log("Stopping transcription", level: .info)
        
        // Stop the audio first
        stopAudioTransmission()
        
        // Set state flags first to prevent any callbacks from re-triggering connections
        isConnected = false
        isConnecting = false
        isRecordingAudio = false
        
        // Make sure to reset transcription text and callbacks
        transcriptionText = ""
        transcriptionCallback = nil
        
        // Close the WebSocket connection
        if let task = webSocketTask {
            task.cancel(with: .goingAway, reason: nil)
            webSocketTask = nil
            logger.log("WebSocket connection closed", level: .info)
        }
    }
    
    // Start audio recording and sending
    func startAudioTransmission(deviceID: String) {
        guard isConnected, !isRecordingAudio else {
            logger.log("Cannot start audio: either not connected or already recording", level: .warning)
            if !isConnected {
                lastError = "Cannot start audio: WebSocket not connected"
            }
            return
        }
        
        logger.log("Starting audio recording and transmission", level: .info)
        
        // Reset audio counters
        audioChunksSent = 0
        
        // Setup audio monitoring
        setupAudioMonitoring(deviceID: deviceID)
        
        isRecordingAudio = true
    }
    
    // Stop audio recording and sending but keep connection
    func stopAudioTransmission() {
        logger.log("Stopping audio transmission only", level: .info)
        
        // Stop the audio timer
        audioTimer?.invalidate()
        audioTimer = nil
        
        // Stop audio recording
        AudioRecorder.shared.stopRecording()
        
        isRecordingAudio = false
    }

    func startLiveTranscriptionWithEphemeralToken(deviceID: String, model: TranscriptionModel = .gpt4oTranscribe, callback: ((String, Bool) -> Void)? = nil) async {
        logger.log("Starting live transcription with ephemeral token", level: .info)
        
        // Set callback
        self.transcriptionCallback = callback
        
        // Connect to WebSocket
        await connectToWebSocketOnly(deviceID: deviceID, model: model)
        
        // Wait for connection to establish
        for _ in 0..<20 { // Wait up to 2 seconds
            if isConnected {
                break
            }
            try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 second
        }
        
        // If connected, start audio
        if isConnected {
            startAudioTransmission(deviceID: deviceID)
        }
    }

    private func processTurnWithText(_ text: String, isFinal: Bool) {
        self.transcriptionText = text
        self.transcriptionCallback?(text, isFinal)
        
        if isFinal {
            self.logger.log("Final transcription: \(text)", level: .info)
            
            // Create a final result for updateHandler if used
            let result = TranscriptionResult(text: text, isFinal: true)
            self.updateHandler?(.success(result))
        } else {
            self.logger.log("Partial transcription: \(text)", level: .debug)
            
            // Create a partial result for updateHandler if used
            let result = TranscriptionResult(text: text, isFinal: false)
            self.updateHandler?(.success(result))
        }
    }
} 