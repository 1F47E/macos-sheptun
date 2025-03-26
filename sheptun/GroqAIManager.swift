import Foundation

class GroqAIManager: AIProvider {
    static let shared = GroqAIManager()
    
    private let logger = Logger.shared
    private let baseURL = "https://api.groq.com/openai/v1"
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
        
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            
            if let httpResponse = response as? HTTPURLResponse {
                return httpResponse.statusCode == 200
            }
            return false
        } catch {
            logger.log("Error testing OpenAI API key: \(error.localizedDescription)", level: .error)
            return false
        }
    }
    
    // Implementation of AIProvider protocol
    // this shit is not working with swift network library
    // maybe its api issue, not sure, got "wrong file type error"
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
        let validModel = (model == "whisper-large-v3" || model == "whisper-large-v3-turbo") ? model : "whisper-large-v3"
        
        // Create a temporary output file
        let tempOutputFile = FileManager.default.temporaryDirectory.appendingPathComponent("groq_output.json")
        
        // Prepare curl arguments
        var arguments = [
            "-s",
            "\(baseURL)/audio/transcriptions",
            "-H", "Authorization: Bearer \(key)",
            "-F", "model=\(validModel)",
            "-F", "file=@\(audioFileURL.path)",
            "-F", "response_format=json"
        ]
        
        if temperature > 0 {
            arguments.append("-F")
            arguments.append("temperature=\(temperature)")
        }
        
        if !language.isEmpty {
            arguments.append("-F")
            arguments.append("language=\(language)")
        }
        
        arguments.append("-X")
        arguments.append("POST")
        arguments.append("-o")
        arguments.append(tempOutputFile.path)
        
        // Execute curl command
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
        process.arguments = arguments
        
        logger.log("Executing curl command: curl \(arguments.joined(separator: " "))", level: .debug)
        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = outputPipe
        
        // Define response structures
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
        
        do {
            try process.run()
            process.waitUntilExit()
            
            // Read output file
            let outputData = try Data(contentsOf: tempOutputFile)
            
            do {
                // First try to decode as error response
                if let errorResponse = try? JSONDecoder().decode(ErrorResponse.self, from: outputData) {
                    logger.log("API returned error: \(errorResponse.error.message)", level: .error)
                    return .failure(APIError.requestFailed(statusCode: 400, message: errorResponse.error.message))
                }
                
                // If not error, decode as transcription
                let response = try JSONDecoder().decode(TranscriptionResponse.self, from: outputData)
                logger.log("Transcription successful", level: .info)
                return .success(response.text)
            } catch {
                let errorOutput = String(data: outputPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "Unknown error"
                logger.log("Failed to decode response: \(error)", level: .error)
                return .failure(APIError.requestFailed(statusCode: Int(process.terminationStatus), message: errorOutput))
            }
        } catch {
            logger.log("Error executing curl command: \(error.localizedDescription)", level: .error)
            return .failure(error)
        }
    }
} 