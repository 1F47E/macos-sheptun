import Foundation
import AVFoundation

class GroqAIManager: AIProvider {
    static let shared = GroqAIManager()
    
    private let logger = Logger.shared
    private let baseURL = "https://api.groq.com/openai/v1"
    var lastError: String?
    
    enum APIError: Error, LocalizedError {
        case invalidURL
        case invalidResponse
        case requestFailed(statusCode: Int, message: String)
        case audioProcessingError(String)
        case networkConnectivity(String)
        case taskCancelled
        case serverError(statusCode: Int, responseBody: String)
        case jsonParsingError(String)
        case authorizationError(String)
        
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
            case .serverError(let statusCode, let responseBody):
                return "Server error with status code \(statusCode): \(responseBody)"
            case .jsonParsingError(let details):
                return "JSON parsing error: \(details)"
            case .authorizationError(let details):
                return "Authorization error: \(details)"
            }
        }
    }
    
    // Get API key from environment variables
    private func getAPIKeyFromEnvironment() -> String? {
        return ProcessInfo.processInfo.environment["GROQ_API_KEY"]
    }
    
    // Test if the API key is valid
    func testAPIKey(apiKey: String) async -> Bool {
        // Try environment variable if empty string is provided
        let key = apiKey.isEmpty ? getAPIKeyFromEnvironment() ?? apiKey : apiKey
        
        guard let url = URL(string: "\(baseURL)/models") else {
            logger.log("Invalid URL for API key test", level: .error)
            return false
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.addValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        
        logger.log("Testing Groq API key (masked): \(maskAPIKey(key))", level: .debug)
        logger.log("Using URL for API test: \(url.absoluteString)", level: .debug)
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            if let httpResponse = response as? HTTPURLResponse {
                let statusCode = httpResponse.statusCode
                let responseString = String(data: data, encoding: .utf8) ?? "Unable to decode response"
                
                logger.log("API key test response status code: \(statusCode)", level: .debug)
                
                if statusCode == 200 {
                    logger.log("API key validation successful", level: .info)
                    return true
                } else {
                    logger.log("API key validation failed with status code: \(statusCode)", level: .error)
                    logger.log("Response body: \(responseString)", level: .debug)
                    return false
                }
            }
            return false
        } catch {
            logger.log("Error testing Groq API key: \(error.localizedDescription)", level: .error)
            return false
        }
    }
    
    private func maskAPIKey(_ key: String) -> String {
        guard key.count > 6 else { return "***" }
        let prefix = String(key.prefix(3))
        let suffix = String(key.suffix(3))
        return "\(prefix)...\(suffix)"
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
        
        // Validate model selection
        let validModel: String
        if model == "whisper-large-v3" || model == "whisper-large-v3-turbo" {
            validModel = model
        } else {
            validModel = "whisper-large-v3"
            logger.log("Invalid model specified, defaulting to whisper-large-v3", level: .warning)
        }
        
        do {
            // First try with a more direct approach that mimics curl better
            let result = await tryDirectFileUpload(
                audioFileURL: audioFileURL,
                apiKey: key,
                model: validModel,
                temperature: temperature,
                language: language
            )
            
            if case .success = result {
                return result
            }
            
            // If direct upload failed, try with multipart manual approach
            logger.log("Direct upload failed, trying with multipart approach", level: .info)
            return await tryMultipartUpload(
                audioFileURL: audioFileURL,
                apiKey: key,
                model: validModel,
                temperature: temperature,
                language: language
            )
        } catch {
            logger.log("Error during Groq API request: \(error.localizedDescription)", level: .error)
            if let nsError = error as NSError? {
                logger.log("Error code: \(nsError.code), domain: \(nsError.domain)", level: .debug)
            }
            return .failure(error)
        }
    }
    
    // Direct file upload that mimics curl approach
    private func tryDirectFileUpload(
        audioFileURL: URL,
        apiKey: String,
        model: String,
        temperature: Double,
        language: String
    ) async -> Result<String, Error> {
        logger.log("Trying direct file upload approach with curl-like parameters", level: .info)
        
        do {
            // Use Curl's approach: Construct a shell command and execute it
            let tempOutputFile = FileManager.default.temporaryDirectory.appendingPathComponent("groq_output.json")
            
            var arguments = [
                "-s",
                "https://api.groq.com/openai/v1/audio/transcriptions",
                "-H", "\"Authorization: Bearer \(apiKey)\"",
                "-F", "model=\(model)",
                "-F", "file=@\(audioFileURL.path)",
                "-F", "temperature=\(temperature)"
            ]
            
            if !language.isEmpty {
                arguments.append(contentsOf: ["-F", "language=\(language)"])
            }
            
            arguments.append("-X")
            arguments.append("POST")
            arguments.append("-o")
            arguments.append(tempOutputFile.path)
            
            // Create a process and execute curl
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
            process.arguments = arguments
            
            logger.log("Executing curl command directly: curl \(arguments.joined(separator: " "))", level: .debug)
            
            let outputPipe = Pipe()
            process.standardOutput = outputPipe
            process.standardError = outputPipe
            
            try process.run()
            process.waitUntilExit()
            
            let outputData = try Data(contentsOf: tempOutputFile)
            
            logger.log("Curl command completed with exit code: \(process.terminationStatus)", level: .debug)
            logger.log("Output data size: \(outputData.count) bytes", level: .debug)
            
            if process.terminationStatus == 0 && outputData.count > 0 {
                // Try to parse the JSON response
                if let json = try JSONSerialization.jsonObject(with: outputData, options: []) as? [String: Any],
                   let text = json["text"] as? String {
                    logger.log("Successfully parsed transcription response from direct curl", level: .debug)
                    return .success(text)
                } else {
                    logger.log("Failed to parse JSON or extract text field from curl output", level: .error)
                    if let responseString = String(data: outputData, encoding: .utf8) {
                        logger.log("Raw curl response: \(responseString)", level: .debug)
                    }
                    return .failure(APIError.jsonParsingError("Failed to extract text field from response"))
                }
            } else {
                let output = String(data: outputPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "No output"
                logger.log("Curl command failed: \(output)", level: .error)
                return .failure(APIError.requestFailed(statusCode: Int(process.terminationStatus), message: output))
            }
        } catch {
            logger.log("Error with direct curl approach: \(error.localizedDescription)", level: .error)
            return .failure(error)
        }
    }
    
    // Multipart form data approach
    private func tryMultipartUpload(
        audioFileURL: URL,
        apiKey: String,
        model: String,
        temperature: Double,
        language: String
    ) async -> Result<String, Error> {
        logger.log("Trying multipart form data upload approach", level: .info)
        
        do {
            // Set up the request
            let url = URL(string: "\(baseURL)/audio/transcriptions")!
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            
            // Try a different approach - using the Alamofire style multipart but implemented directly
            // Generate a unique boundary string for multipart/form-data
            let boundary = "Boundary-\(UUID().uuidString)"
            let contentType = "multipart/form-data; boundary=\(boundary)"
            request.setValue(contentType, forHTTPHeaderField: "Content-Type")
            
            var httpBody = Data()
            
            // Function to append form field
            func appendFormField(named name: String, value: String) {
                httpBody.append("--\(boundary)\r\n".data(using: .utf8)!)
                httpBody.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
                httpBody.append("\(value)\r\n".data(using: .utf8)!)
            }
            
            // Add model field
            appendFormField(named: "model", value: model)
            
            // Add temperature field
            appendFormField(named: "temperature", value: String(temperature))
            
            // Add language field if present
            if !language.isEmpty {
                appendFormField(named: "language", value: language)
            }
            
            // Add file data - this is the most important part
            httpBody.append("--\(boundary)\r\n".data(using: .utf8)!)
            httpBody.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(audioFileURL.lastPathComponent)\"\r\n".data(using: .utf8)!)
            
            // Set the content type based on file extension
            let fileExtension = audioFileURL.pathExtension.lowercased()
            let fileContentType: String
            
            switch fileExtension {
            case "m4a":
                fileContentType = "audio/mp4"
            case "mp3":
                fileContentType = "audio/mpeg"
            case "wav":
                fileContentType = "audio/wav"
            default:
                fileContentType = "application/octet-stream"
            }
            
            httpBody.append("Content-Type: \(fileContentType)\r\n\r\n".data(using: .utf8)!)
            
            // Read the file data
            let fileData = try Data(contentsOf: audioFileURL)
            httpBody.append(fileData)
            httpBody.append("\r\n".data(using: .utf8)!)
            
            // Close the form
            httpBody.append("--\(boundary)--\r\n".data(using: .utf8)!)
            
            // Log the file info for debugging
            logger.log("File path: \(audioFileURL.path)", level: .debug)
            logger.log("File size: \(fileData.count) bytes", level: .debug)
            logger.log("File content type: \(fileContentType)", level: .debug)
            logger.log("Total request body size: \(httpBody.count) bytes", level: .debug)
            
            // Create an equivalent curl command for debugging
            let curlCommand = """
            curl -X POST "\(url.absoluteString)" \\
              -H "Authorization: Bearer [REDACTED]" \\
              -H "Content-Type: multipart/form-data; boundary=\(boundary)" \\
              -F "model=\(model)" \\
              -F "temperature=\(temperature)" \\
              -F "language=\(language)" \\
              -F "file=@\(audioFileURL.path)"
            """
            logger.log("Equivalent curl command: \(curlCommand)", level: .debug)
            
            // For debugging, write the request body to a file
            let tempDir = FileManager.default.temporaryDirectory
            let tempRequestPath = tempDir.appendingPathComponent("groq_request_debug.txt")
            try? httpBody.write(to: tempRequestPath)
            logger.log("Debug request body written to: \(tempRequestPath.path)", level: .debug)
            
            // Create a URL request with the file as the content
            request.httpBody = httpBody
            
            let startTime = Date()
            
            // Send the request directly with the http body rather than using upload
            logger.log("Sending request directly with http body...", level: .debug)
            let (responseData, response) = try await URLSession.shared.data(for: request)
            
            // Calculate response time
            let responseTime = Date().timeIntervalSince(startTime)
            logger.log("Groq API responded in \(String(format: "%.2f", responseTime)) seconds", level: .info)
            
            return processResponse(responseData: responseData, response: response)
        } catch {
            logger.log("Error during multipart upload: \(error.localizedDescription)", level: .error)
            return .failure(error)
        }
    }
    
    // Process API response
    private func processResponse(responseData: Data, response: URLResponse) -> Result<String, Error> {
        // Log response size
        logger.log("Response data size: \(responseData.count) bytes", level: .debug)
        
        // Preview response data as string
        let previewLength = min(1000, responseData.count)
        if let previewString = String(data: responseData.prefix(previewLength), encoding: .utf8) {
            logger.log("Response preview: \(previewString)\(responseData.count > previewLength ? "..." : "")", level: .debug)
        }
        
        // Check for HTTP status code
        guard let httpResponse = response as? HTTPURLResponse else {
            logger.log("Invalid HTTP response received", level: .error)
            return .failure(NSError(domain: "GroqAIManager", code: 3, userInfo: [NSLocalizedDescriptionKey: "Invalid HTTP response"]))
        }
        
        // Log response details for debugging
        let responseString = String(data: responseData, encoding: .utf8) ?? "Unable to decode response"
        logger.log("Response status code: \(httpResponse.statusCode)", level: .debug)
        
        // Log response headers
        var responseHeadersLog = "Response headers: "
        for (key, value) in httpResponse.allHeaderFields {
            responseHeadersLog += "\(key): \(value), "
        }
        logger.log(responseHeadersLog, level: .debug)
        
        // Log detailed response for error cases
        if httpResponse.statusCode != 200 {
            logger.log("Response body: \(responseString)", level: .error)
        }
        
        // Special handling for 401 errors
        if httpResponse.statusCode == 401 {
            logger.log("Authorization error (401) - API key may be invalid or expired", level: .error)
            
            // Try to extract detailed error message from JSON response
            do {
                if let json = try JSONSerialization.jsonObject(with: responseData, options: []) as? [String: Any],
                   let error = json["error"] as? [String: Any],
                   let message = error["message"] as? String {
                    logger.log("Error details from Groq: \(message)", level: .error)
                    return .failure(APIError.authorizationError(message))
                }
            } catch {
                logger.log("Could not parse error details from response: \(error.localizedDescription)", level: .debug)
            }
            
            return .failure(APIError.authorizationError("Unauthorized - API key may be invalid or expired"))
        }
        
        // Check if response is successful (2xx status code)
        if httpResponse.statusCode >= 200 && httpResponse.statusCode < 300 {
            do {
                // Parse the JSON response
                if let json = try JSONSerialization.jsonObject(with: responseData, options: []) as? [String: Any],
                   let text = json["text"] as? String {
                    // Return only the text field
                    logger.log("Successfully parsed transcription response", level: .debug)
                    return .success(text)
                } else {
                    logger.log("Failed to parse JSON or extract text field", level: .error)
                    logger.log("Raw response: \(responseString)", level: .debug)
                    return .failure(APIError.jsonParsingError("Failed to extract text field from response"))
                }
            } catch {
                logger.log("JSON parsing error: \(error.localizedDescription)", level: .error)
                logger.log("Raw response: \(responseString)", level: .debug)
                return .failure(APIError.jsonParsingError(error.localizedDescription))
            }
        } else {
            // Handle server errors (500+) specifically
            if httpResponse.statusCode >= 500 {
                logger.log("Server error \(httpResponse.statusCode) received: \(responseString)", level: .error)
                return .failure(APIError.serverError(statusCode: httpResponse.statusCode, responseBody: responseString))
            }
            
            // For any other error, try to extract detailed message from the response
            do {
                if let json = try JSONSerialization.jsonObject(with: responseData, options: []) as? [String: Any],
                   let error = json["error"] as? [String: Any],
                   let message = error["message"] as? String {
                    logger.log("Error details from Groq: \(message)", level: .error)
                    return .failure(APIError.requestFailed(statusCode: httpResponse.statusCode, message: message))
                }
            } catch {
                logger.log("Could not parse error details: \(error.localizedDescription)", level: .debug)
            }
            
            return .failure(NSError(domain: "GroqAIManager", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "Request failed with HTTP status code \(httpResponse.statusCode)"]))
        }
    }
} 