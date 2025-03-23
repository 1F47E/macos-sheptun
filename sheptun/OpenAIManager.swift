import Foundation
import AVFoundation

class OpenAIManager: AIProvider {
    static let shared = OpenAIManager()
    
    private let logger = Logger.shared
    private let baseURL = "https://api.openai.com/v1"
    private let settings = SettingsManager.shared
    var lastError: String?
    var isRecordingAudio = false
    
    // Deprecated - kept for compatibility but not used directly 
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
        case serverError(statusCode: Int, responseBody: String)
        
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
    
    // Get API key from environment variables
    private func getAPIKeyFromEnvironment() -> String? {
        return ProcessInfo.processInfo.environment["OPENAI_API_KEY"]
    }
    
    // Implementation of AIProvider protocol
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
    func transcribeAudio(
        audioFileURL: URL,
        apiKey: String,
        model: String,
        temperature: Double,
        language: String
    ) async -> Result<String, Error> {
        // Try environment variable if empty string is provided
        let key = apiKey.isEmpty ? getAPIKeyFromEnvironment() ?? apiKey : apiKey
        
        do {
            // Set up the request
            let url = URL(string: "https://api.openai.com/v1/audio/transcriptions")!
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
            
            // Generate a unique boundary string for multipart/form-data
            let boundary = "Boundary-\(UUID().uuidString)"
            request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
            
            // Create multipart/form-data body
            var data = Data()
            
            // Add model parameter
            data.append("--\(boundary)\r\n".data(using: .utf8)!)
            data.append("Content-Disposition: form-data; name=\"model\"\r\n\r\n".data(using: .utf8)!)
            data.append("\(model)\r\n".data(using: .utf8)!)
            
            // Add language parameter if specified
            if !language.isEmpty {
                data.append("--\(boundary)\r\n".data(using: .utf8)!)
                data.append("Content-Disposition: form-data; name=\"language\"\r\n\r\n".data(using: .utf8)!)
                data.append("\(language)\r\n".data(using: .utf8)!)
            }
            
            // Add temperature parameter
            data.append("--\(boundary)\r\n".data(using: .utf8)!)
            data.append("Content-Disposition: form-data; name=\"temperature\"\r\n\r\n".data(using: .utf8)!)
            data.append("\(temperature)\r\n".data(using: .utf8)!)
            
            // Add response_format parameter
            data.append("--\(boundary)\r\n".data(using: .utf8)!)
            data.append("Content-Disposition: form-data; name=\"response_format\"\r\n\r\n".data(using: .utf8)!)
            data.append("text\r\n".data(using: .utf8)!)
            
            // Add file data
            data.append("--\(boundary)\r\n".data(using: .utf8)!)
            data.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(audioFileURL.lastPathComponent)\"\r\n".data(using: .utf8)!)
            
            // Set the correct Content-Type based on file extension
            let fileExtension = audioFileURL.pathExtension.lowercased()
            let contentType: String
            
            switch fileExtension {
            case "m4a":
                contentType = "audio/mp4"
            case "mp3", "mpeg", "mpga":
                contentType = "audio/mpeg"
            case "wav":
                contentType = "audio/wav"
            case "mp4":
                contentType = "audio/mp4"
            case "ogg", "oga":
                contentType = "audio/ogg"
            case "flac":
                contentType = "audio/flac"
            case "webm":
                contentType = "audio/webm"
            default:
                contentType = "audio/mpeg" // Default fallback
            }
            
            data.append("Content-Type: \(contentType)\r\n\r\n".data(using: .utf8)!)
            
            // Read file data directly from the file
            let fileData = try Data(contentsOf: audioFileURL)
            
            // Log file header for debugging (first 32 bytes as hex)
            let headerSize = min(fileData.count, 32)
            if headerSize > 0 {
                let fileHeaderHex = fileData.prefix(headerSize).map { String(format: "%02x", $0) }.joined(separator: " ")
                logger.log("File header (first \(headerSize) bytes): \(fileHeaderHex)", level: .debug)
                
                // Try to detect file format from magic numbers
                let formatInfo = detectFileFormat(data: fileData)
                logger.log("File format detection: \(formatInfo)", level: .debug)
            }
            
            data.append(fileData)
            data.append("\r\n".data(using: .utf8)!)
            
            // Close the boundary
            data.append("--\(boundary)--\r\n".data(using: .utf8)!)
            
            // Log request details for debugging
            logger.log("Sending API request to: \(url.absoluteString)", level: .debug)
            logger.log("Request headers: \(request.allHTTPHeaderFields ?? [:])", level: .debug)
            logger.log("Request parameters: model=\(model), language=\(language), temperature=\(temperature), response_format=text", level: .debug)
            logger.log("Audio file size: \(fileData.count) bytes, contentType: \(contentType), format: \(fileExtension)", level: .debug)
            
            let startTime = Date()
            
            // Send the request
            let (responseData, response) = try await URLSession.shared.upload(for: request, from: data)
            
            // Calculate response time
            let responseTime = Date().timeIntervalSince(startTime)
            logger.log("OpenAI API responded in \(String(format: "%.2f", responseTime)) seconds", level: .info)
            
            // Check for HTTP status code
            guard let httpResponse = response as? HTTPURLResponse else {
                return .failure(NSError(domain: "OpenAIManager", code: 3, userInfo: [NSLocalizedDescriptionKey: "Invalid HTTP response"]))
            }
            
            // Log all responses for debugging
            let responseString = String(data: responseData, encoding: .utf8) ?? "Unable to decode response"
            logger.log("Response status code: \(httpResponse.statusCode)", level: .debug)
            logger.log("Response body: \(responseString)", level: .debug)
            
            // Check if response is successful (2xx status code)
            if httpResponse.statusCode >= 200 && httpResponse.statusCode < 300 {
                if let transcription = String(data: responseData, encoding: .utf8) {
                    return .success(transcription)
                } else {
                    return .failure(NSError(domain: "OpenAIManager", code: 4, userInfo: [NSLocalizedDescriptionKey: "Failed to decode transcription text"]))
                }
            } else {
                // Handle server errors (500+) specifically
                if httpResponse.statusCode >= 500 {
                    logger.log("Server error \(httpResponse.statusCode) received: \(responseString)", level: .error)
                    return .failure(APIError.serverError(statusCode: httpResponse.statusCode, responseBody: responseString))
                }
                
                // Try to parse the error message from the API
                if let responseString = String(data: responseData, encoding: .utf8) {
                    logger.log("=== RESPONSE HEADERS ===", level: .debug)
                    logger.log("Status Code: \(httpResponse.statusCode)", level: .debug)
                    for (key, value) in httpResponse.allHeaderFields {
                        logger.log("\(key): \(value)", level: .debug)
                    }
                    logger.log("=== END RESPONSE HEADERS ===", level: .debug)
                    
                    logger.log("=== RESPONSE BODY ===", level: .debug)
                    logger.log(responseString, level: .debug) 
                    logger.log("=== END RESPONSE BODY ===", level: .debug)
                    
                    // Try to extract error message from JSON
                    if let data = responseString.data(using: .utf8) {
                        do {
                            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                               let error = json["error"] as? [String: Any] {
                                
                                let message = error["message"] as? String ?? "Unknown error"
                                let errorType = error["type"] as? String ?? "unknown_error"
                                let errorCode = error["code"] as? String ?? "no_code"
                                
                                logger.log("API error: type=\(errorType), code=\(errorCode), message=\(message)", level: .error)
                                logger.log("File details: name=\(audioFileURL.lastPathComponent), size=\(fileData.count) bytes, contentType=\(contentType)", level: .error)
                                
                                return .failure(NSError(domain: "OpenAIManager", code: httpResponse.statusCode, userInfo: [
                                    NSLocalizedDescriptionKey: "Request failed with status code \(httpResponse.statusCode): \(message)",
                                    "errorType": errorType,
                                    "errorCode": errorCode
                                ]))
                            }
                        } catch {
                            logger.log("Failed to parse error JSON: \(error.localizedDescription)", level: .error)
                        }
                    }
                }
                
                return .failure(NSError(domain: "OpenAIManager", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "Request failed with HTTP status code \(httpResponse.statusCode)"]))
            }
        } catch {
            logger.log("Error during API request: \(error.localizedDescription)", level: .error)
            return .failure(error)
        }
    }
    
    // Helper function to detect file format from data
    private func detectFileFormat(data: Data) -> String {
        guard data.count >= 12 else { return "File too small to detect format" }
        
        // Check for WAV
        if data.count >= 12 && 
           data[0] == 0x52 && data[1] == 0x49 && data[2] == 0x46 && data[3] == 0x46 && // "RIFF"
           data[8] == 0x57 && data[9] == 0x41 && data[10] == 0x56 && data[11] == 0x45 { // "WAVE"
            return "WAV format detected (RIFF/WAVE headers)"
        }
        
        // Check for MP3
        if data.count >= 3 && 
           ((data[0] == 0x49 && data[1] == 0x44 && data[2] == 0x33) || // ID3 tag
            (data[0] == 0xFF && (data[1] & 0xE0) == 0xE0)) { // MP3 sync word
            return "MP3 format detected"
        }
        
        // Check for M4A/AAC (MPEG-4)
        if data.count >= 12 && 
           ((data[4] == 0x66 && data[5] == 0x74 && data[6] == 0x79 && data[7] == 0x70) || // ftyp
            (data[4] == 0x6D && data[5] == 0x6F && data[6] == 0x6F && data[7] == 0x76)) { // moov
            return "M4A/AAC format detected (MPEG-4 container)"
        }
        
        return "Unknown format, no standard header detected"
    }
}

// Extension to get PCM data from AVAudioPCMBuffer
extension AVAudioPCMBuffer {
    func data() -> Data {
        let channelCount = Int(format.channelCount)
        let frameCount = Int(frameLength)
        let sampleCount = frameCount * channelCount
        
        switch format.commonFormat {
        case .pcmFormatFloat32:
            if let floatData = floatChannelData {
                let stride = format.streamDescription.pointee.mBytesPerFrame
                let byteCount = Int(frameLength) * Int(stride)
                return Data(bytes: floatData[0], count: byteCount)
            }
        case .pcmFormatInt16:
            if let int16Data = int16ChannelData {
                let stride = 2 // Int16 = 2 bytes
                let byteCount = sampleCount * stride
                return Data(bytes: int16Data[0], count: byteCount)
            }
        case .pcmFormatInt32:
            if let int32Data = int32ChannelData {
                let stride = 4 // Int32 = 4 bytes
                let byteCount = sampleCount * stride
                return Data(bytes: int32Data[0], count: byteCount)
            }
        default:
            break
        }
        
        // Default - create empty data
        return Data()
    }
} 