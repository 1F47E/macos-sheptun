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
        
        let startTime = Date()
        logger.log("Starting audio transcription with curl using model: \(model)", level: .info)
        
        let tempDir = FileManager.default.temporaryDirectory.path
        let outputPath = "\(tempDir)/transcription_response.txt"
        
        // Build the curl command
        var arguments: [String] = []
        arguments.append("-X")
        arguments.append("POST")
        arguments.append("https://api.openai.com/v1/audio/transcriptions")
        arguments.append("-H")
        arguments.append("Authorization: Bearer \(key)")
        arguments.append("-H")
        arguments.append("Content-Type: multipart/form-data")
        arguments.append("-F")
        arguments.append("model=\(model)")
        arguments.append("-F")
        arguments.append("temperature=\(temperature)")
        arguments.append("-F")
        arguments.append("response_format=text")
        
        if !language.isEmpty {
            arguments.append("-F")
            arguments.append("language=\(language)")
        }
        
        arguments.append("-F")
        arguments.append("file=@\(audioFileURL.path)")
        arguments.append("-o")
        arguments.append(outputPath)
        
        // Use Process to run curl
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
        process.arguments = arguments
        
        let pipe = Pipe()
        process.standardError = pipe
        
        do {
            try process.run()
            process.waitUntilExit()
            
            // Calculate response time
            let responseTime = Date().timeIntervalSince(startTime)
            logger.log("OpenAI API responded in \(String(format: "%.2f", responseTime)) seconds", level: .info)
            
            // Check exit status
            let status = process.terminationStatus
            if status != 0 {
                let errorData = pipe.fileHandleForReading.readDataToEndOfFile()
                let errorMessage = String(data: errorData, encoding: .utf8) ?? "Unknown error"
                logger.log("curl command failed with status \(status): \(errorMessage)", level: .error)
                return .failure(APIError.requestFailed(statusCode: Int(status), message: errorMessage))
            }
            
            // Read the response from the file
            if let transcription = try? String(contentsOfFile: outputPath, encoding: .utf8) {
                // Clean up the temp file
                try? FileManager.default.removeItem(atPath: outputPath)
                
                // Return the transcription
                return .success(transcription.trimmingCharacters(in: .whitespacesAndNewlines))
            } else {
                logger.log("Failed to read transcription response from file", level: .error)
                return .failure(APIError.invalidResponse)
            }
        } catch {
            logger.log("Error executing curl: \(error.localizedDescription)", level: .error)
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

// // Extension to get PCM data from AVAudioPCMBuffer
// extension AVAudioPCMBuffer {
//     func data() -> Data {
//         let channelCount = Int(format.channelCount)
//         let frameCount = Int(frameLength)
//         let sampleCount = frameCount * channelCount
//         
//         switch format.commonFormat {
//         case .pcmFormatFloat32:
//             if let floatData = floatChannelData {
//                 let stride = format.streamDescription.pointee.mBytesPerFrame
//                 let byteCount = Int(frameLength) * Int(stride)
//                 return Data(bytes: floatData[0], count: byteCount)
//             }
//         case .pcmFormatInt16:
//             if let int16Data = int16ChannelData {
//                 let stride = 2 // Int16 = 2 bytes
//                 let byteCount = sampleCount * stride
//                 return Data(bytes: int16Data[0], count: byteCount)
//             }
//         case .pcmFormatInt32:
//             if let int32Data = int32ChannelData {
//                 let stride = 4 // Int32 = 4 bytes
//                 let byteCount = sampleCount * stride
//                 return Data(bytes: int32Data[0], count: byteCount)
//             }
//         default:
//             break
//         }
//         
//         // Default - create empty data
//         return Data()
//     }
// } 