import Foundation

protocol AIProvider {
    var lastError: String? { get set }
    
    func testAPIKey(apiKey: String) async -> Bool
    
    func transcribeAudio(
        audioFileURL: URL,
        apiKey: String,
        model: String,
        temperature: Double,
        language: String
    ) async -> Result<String, Error>
}

enum AIProviderType {
    case openAI
    case groq
    case deepgram
}

class AIProviderFactory {
    static func getProvider(type: AIProviderType) -> AIProvider {
        switch type {
        case .openAI:
            return OpenAIManager.shared
        case .groq:
            return GroqAIManager.shared
        case .deepgram:
            return DeepgramManager.shared
        }
    }
} 