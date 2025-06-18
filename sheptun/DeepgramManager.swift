import Foundation

class DeepgramManager: AIProvider {
    static let shared = DeepgramManager()
    
    private let logger = Logger.shared
    private let baseURL = "https://api.deepgram.com/v1"
    var lastError: String?
    
    enum APIError: Error, LocalizedError {
        case invalidURL
        case invalidResponse
        case requestFailed(statusCode: Int, message: String)
        
        var errorDescription: String? {
            switch self {
            case .invalidURL:
                return "Invalid URL"
            case .invalidResponse:
                return "Invalid response from server"
            case .requestFailed(let statusCode, let message):
                return "Request failed with status code \(statusCode): \(message)"
            }
        }
    }
    
    // Get API key from environment variables
    private func getAPIKeyFromEnvironment() -> String? {
        return ProcessInfo.processInfo.environment["DEEPGRAM_API_KEY"]
    }
    
    // Test if the API key is valid
    func testAPIKey(apiKey: String) async -> Bool {
        // Try environment variable if empty string is provided
        let key = apiKey.isEmpty ? getAPIKeyFromEnvironment() ?? apiKey : apiKey
        
        logger.log("Testing Deepgram API key: \(key.prefix(4))...\(key.suffix(4))", level: .info)
        
        // Use the models endpoint to test API key validity
        guard let url = URL(string: "\(baseURL)/models") else {
            logger.log("Invalid URL for API key test: \(baseURL)/models", level: .error)
            return false
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.addValue("Token \(key)", forHTTPHeaderField: "Authorization")
        
        logger.log("Testing Deepgram API key with URL: \(url.absoluteString)", level: .debug)
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            if let httpResponse = response as? HTTPURLResponse {
                logger.log("Deepgram API key test response status: \(httpResponse.statusCode)", level: .info)
                
                if httpResponse.statusCode != 200 {
                    let responseBody = String(data: data, encoding: .utf8) ?? "Unable to decode response"
                    logger.log("Deepgram API key test failed - Status: \(httpResponse.statusCode), Response: \(responseBody)", level: .error)
                    lastError = "API key test failed with status \(httpResponse.statusCode): \(responseBody)"
                } else {
                    logger.log("Deepgram API key test successful", level: .info)
                    // Try to parse the response to see available models
                    if let jsonData = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
                       let sttModels = jsonData["stt"] as? [[String: Any]] {
                        logger.log("Available STT models count: \(sttModels.count)", level: .debug)
                    }
                }
                
                return httpResponse.statusCode == 200
            }
            
            logger.log("Deepgram API key test failed - Invalid response type", level: .error)
            lastError = "Invalid response type from API"
            return false
        } catch {
            logger.log("Error testing Deepgram API key: \(error.localizedDescription)", level: .error)
            logger.log("Full error details: \(error)", level: .debug)
            lastError = "Network error: \(error.localizedDescription)"
            return false
        }
    }
    
    // Implementation of AIProvider protocol
    func transcribeAudio(
        audioFileURL: URL,
        apiKey: String,
        model: String,
        temperature: Double,
        language: String
    ) async -> Result<String, Error> {
        // Try environment variable if empty string is provided
        let key = apiKey.isEmpty ? getAPIKeyFromEnvironment() ?? apiKey : apiKey
        
        // Validate model selection - default to nova-3 if not specified
        let validModel = (model == "nova-2" || model == "nova" || model == "nova-3") ? model : "nova-3"
        
        let startTime = Date()
        logger.log("Starting audio transcription with curl using Deepgram model: \(validModel)", level: .info)
        
        // Create a temporary output file
        let tempOutputFile = FileManager.default.temporaryDirectory.appendingPathComponent("deepgram_output.json")
        
        // Build the URL with query parameters
        var urlComponents = URLComponents(string: "\(baseURL)/listen")!
        urlComponents.queryItems = [
            URLQueryItem(name: "model", value: validModel),
            URLQueryItem(name: "smart_format", value: "true"),
            URLQueryItem(name: "detect_language", value: "true")
        ]
        
        if !language.isEmpty && language != "en" {
            urlComponents.queryItems?.append(URLQueryItem(name: "language", value: language))
        }
        
        // Log the request details
        logger.log("Deepgram API URL: \(urlComponents.url?.absoluteString ?? "invalid")", level: .debug)
        logger.log("Using API key: \(key.prefix(8))....\(key.suffix(4))", level: .debug)
        
        // Note: Deepgram doesn't support temperature parameter
        if temperature > 0 {
            logger.log("Note: Deepgram API does not support temperature parameter, ignoring", level: .info)
        }
        
        // Detect content type based on file extension
        let fileExtension = audioFileURL.pathExtension.lowercased()
        let contentType: String
        switch fileExtension {
        case "m4a":
            contentType = "audio/mp4"
        case "wav":
            contentType = "audio/wav"
        case "mp3":
            contentType = "audio/mp3"
        default:
            contentType = "audio/mpeg"
        }
        
        logger.log("Using Content-Type: \(contentType) for file: \(audioFileURL.lastPathComponent)", level: .debug)
        
        // Prepare curl arguments
        let arguments = [
            "-s",  // Silent mode - no progress bar
            "-X", "POST",
            urlComponents.url!.absoluteString,
            "-H", "Authorization: Token \(key)",
            "-H", "Content-Type: \(contentType)",
            "--data-binary", "@\(audioFileURL.path)",
            "-o", tempOutputFile.path,
            "-w", "\\nHTTP_STATUS_CODE:%{http_code}"  // Write HTTP status code with marker
        ]
        
        // Execute curl command
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
        process.arguments = arguments
        
        // Log the full curl command for debugging
        let curlCommand = "curl " + arguments.joined(separator: " ")
        logger.log("Executing curl command: \(curlCommand)", level: .debug)
        logger.log("Audio file path: \(audioFileURL.path)", level: .debug)
        logger.log("Audio file exists: \(FileManager.default.fileExists(atPath: audioFileURL.path))", level: .debug)
        
        // Check file size
        if let fileAttributes = try? FileManager.default.attributesOfItem(atPath: audioFileURL.path),
           let fileSize = fileAttributes[.size] as? Int64 {
            logger.log("Audio file size: \(fileSize) bytes", level: .debug)
        }
        
        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = outputPipe
        
        // Define response structures
        struct ErrorResponse: Decodable {
            let err_code: String?
            let err_msg: String?
            let message: String?
        }
        
        struct DeepgramResponse: Decodable {
            struct Results: Decodable {
                struct Channel: Decodable {
                    struct Alternative: Decodable {
                        let transcript: String
                        let confidence: Double?
                    }
                    let alternatives: [Alternative]?
                }
                let channels: [Channel]?
            }
            let results: Results?
        }
        
        do {
            try process.run()
            process.waitUntilExit()
            
            // Calculate response time
            let responseTime = Date().timeIntervalSince(startTime)
            logger.log("Deepgram API responded in \(String(format: "%.2f", responseTime)) seconds", level: .info)
            
            // Read curl output (includes HTTP status code)
            let curlOutput = outputPipe.fileHandleForReading.readDataToEndOfFile()
            let curlOutputString = String(data: curlOutput, encoding: .utf8) ?? ""
            
            // Extract HTTP status code from curl output
            var httpStatusCode = "0"
            if let statusRange = curlOutputString.range(of: "HTTP_STATUS_CODE:") {
                let statusStart = curlOutputString.index(statusRange.upperBound, offsetBy: 0)
                let statusSubstring = curlOutputString[statusStart...]
                httpStatusCode = statusSubstring.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            logger.log("Deepgram API HTTP status code: \(httpStatusCode)", level: .info)
            
            // Check exit status
            let status = process.terminationStatus
            if status != 0 {
                logger.log("curl command failed with status \(status): \(curlOutputString)", level: .error)
                return .failure(APIError.requestFailed(statusCode: Int(status), message: curlOutputString))
            }
            
            // Read output file
            let outputData = try Data(contentsOf: tempOutputFile)
            
            // Clean up temp file
            try? FileManager.default.removeItem(at: tempOutputFile)
            
            do {
                // Log the raw response for debugging
                let responseString = String(data: outputData, encoding: .utf8) ?? "Unable to decode response"
                logger.log("Deepgram API raw response: \(responseString)", level: .debug)
                
                // Check HTTP status code first
                if httpStatusCode != "200" {
                    // Try to decode as error response
                    if let errorResponse = try? JSONDecoder().decode(ErrorResponse.self, from: outputData) {
                        let errorMessage = errorResponse.err_msg ?? errorResponse.message ?? "Unknown error"
                        logger.log("API returned error: \(errorMessage)", level: .error)
                        return .failure(APIError.requestFailed(statusCode: Int(httpStatusCode) ?? 400, message: errorMessage))
                    } else {
                        let responseBody = String(data: outputData, encoding: .utf8) ?? "Unable to decode response"
                        logger.log("API error without proper error format: \(responseBody)", level: .error)
                        return .failure(APIError.requestFailed(statusCode: Int(httpStatusCode) ?? 400, message: responseBody))
                    }
                }
                
                // If not error, decode as transcription response
                let response = try JSONDecoder().decode(DeepgramResponse.self, from: outputData)
                
                // Extract transcript from the nested structure
                if let channels = response.results?.channels,
                   !channels.isEmpty,
                   let alternatives = channels[0].alternatives,
                   !alternatives.isEmpty {
                    let transcript = alternatives[0].transcript
                    logger.log("Transcription successful", level: .info)
                    return .success(transcript)
                } else {
                    logger.log("No transcript found in response", level: .error)
                    logger.log("Response structure: channels=\(response.results?.channels?.count ?? 0)", level: .debug)
                    return .failure(APIError.invalidResponse)
                }
            } catch {
                let errorOutput = String(data: outputPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "Unknown error"
                logger.log("Failed to decode response: \(error)", level: .error)
                logger.log("Response data: \(String(data: outputData, encoding: .utf8) ?? "Unable to decode")", level: .error)
                return .failure(APIError.requestFailed(statusCode: Int(process.terminationStatus), message: errorOutput))
            }
        } catch {
            logger.log("Error executing curl command: \(error.localizedDescription)", level: .error)
            return .failure(error)
        }
    }
}