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
} 