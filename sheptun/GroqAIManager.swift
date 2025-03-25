import Foundation

class GroqAIManager: AIProvider {
    static let shared = GroqAIManager()
    
    private let logger = Logger.shared
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
        // Simple implementation - just return true for now
        return true
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
        let validModel = (model == "whisper-large-v3" || model == "whisper-large-v3-turbo") ? model : "whisper-large-v3"
        
        // Create a temporary output file
        let tempOutputFile = FileManager.default.temporaryDirectory.appendingPathComponent("groq_output.json")
        
        // Prepare curl arguments
        var arguments = [
            "-s",
            "https://api.groq.com/openai/v1/audio/transcriptions",
            "-H", "Authorization: Bearer \(key)",
            "-F", "model=\(validModel)",
            "-F", "file=@\(audioFileURL.path)",
            "-F", "response_format=text"
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
        
        do {
            try process.run()
            process.waitUntilExit()
            
            // Read output file
            let outputData = try Data(contentsOf: tempOutputFile)
            let responseText = String(data: outputData, encoding: .utf8) ?? ""
            
            if process.terminationStatus == 0 && !responseText.isEmpty {
                logger.log("Transcription successful", level: .info)
                return .success(responseText)
            } else {
                let errorOutput = String(data: outputPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "Unknown error"
                logger.log("Curl command failed: \(errorOutput)", level: .error)
                return .failure(APIError.requestFailed(statusCode: Int(process.terminationStatus), message: errorOutput))
            }
        } catch {
            logger.log("Error executing curl command: \(error.localizedDescription)", level: .error)
            return .failure(error)
        }
    }
} 