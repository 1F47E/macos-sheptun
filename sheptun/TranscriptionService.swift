import Foundation
import AppKit

/// Centralized service for handling all audio transcription operations
/// This service encapsulates the transcription logic and provides a single interface
/// for the rest of the app to use, following the Single Responsibility Principle
@MainActor
class TranscriptionService: ObservableObject {
    static let shared = TranscriptionService()
    
    private let settings = SettingsManager.shared
    private let logger = Logger.shared
    
    private init() {
        logger.log("TranscriptionService initialized", level: .info)
    }
    
    /// Result type for transcription operations that includes metadata
    struct TranscriptionResult {
        let text: String
        let provider: AIProviderType
        let model: String
        let language: String
        let duration: TimeInterval?
    }
    
    /// Main transcription method that handles all the provider selection and API calls
    func transcribeAudioFile(_ audioFileURL: URL) async -> Result<TranscriptionResult, Error> {
        logger.log("Starting transcription for file: \(audioFileURL.lastPathComponent)", level: .info)
        
        // Validate file exists
        guard FileManager.default.fileExists(atPath: audioFileURL.path) else {
            logger.log("Audio file not found at path: \(audioFileURL.path)", level: .error)
            return .failure(TranscriptionError.fileNotFound)
        }
        
        // Get current configuration
        let provider = settings.getCurrentAIProvider()
        let aiManager = AIProviderFactory.getProvider(type: provider)
        let apiKey = settings.getCurrentAPIKey()
        
        // Validate API key
        guard !apiKey.isEmpty else {
            logger.log("No API key configured for provider: \(provider)", level: .error)
            return .failure(TranscriptionError.noAPIKey(provider: String(describing: provider)))
        }
        
        // Log transcription parameters
        logger.log("""
            Transcription parameters:
            - Provider: \(provider)
            - Model: \(settings.transcriptionModel)
            - Language: \(settings.transcriptionLanguage)
            - Temperature: \(settings.transcriptionTemperature)
            """, level: .debug)
        
        let startTime = Date()
        
        // Perform transcription
        let result = await aiManager.transcribeAudio(
            audioFileURL: audioFileURL,
            apiKey: apiKey,
            model: settings.transcriptionModel,
            temperature: settings.transcriptionTemperature,
            language: settings.transcriptionLanguage
        )
        
        let duration = Date().timeIntervalSince(startTime)
        
        // Transform result to include metadata
        switch result {
        case .success(let text):
            logger.log("Transcription successful. Duration: \(String(format: "%.2f", duration))s", level: .info)
            
            let transcriptionResult = TranscriptionResult(
                text: text,
                provider: provider,
                model: settings.transcriptionModel,
                language: settings.transcriptionLanguage,
                duration: duration
            )
            
            // Post notification for successful transcription
            NotificationCenter.default.post(
                name: NSNotification.Name("TranscriptionCompleted"),
                object: nil,
                userInfo: [
                    "transcription": text,
                    "provider": String(describing: provider),
                    "duration": duration
                ]
            )
            
            return .success(transcriptionResult)
            
        case .failure(let error):
            logger.log("Transcription failed: \(error.localizedDescription)", level: .error)
            
            // Report to Sentry
            SentryManager.shared.captureError(error, context: [
                "provider": String(describing: provider),
                "model": settings.transcriptionModel,
                "language": settings.transcriptionLanguage,
                "microphone": settings.selectedMicrophoneID
            ])
            
            // Post notification for failed transcription
            NotificationCenter.default.post(
                name: NSNotification.Name("TranscriptionFailed"),
                object: nil,
                userInfo: [
                    "error": error,
                    "provider": String(describing: provider)
                ]
            )
            
            return .failure(error)
        }
    }
    
    /// Test the current API key configuration
    func testCurrentAPIKey() async -> Bool {
        let provider = settings.getCurrentAIProvider()
        let aiManager = AIProviderFactory.getProvider(type: provider)
        let apiKey = settings.getCurrentAPIKey()
        
        guard !apiKey.isEmpty else {
            logger.log("No API key to test for provider: \(provider)", level: .warning)
            return false
        }
        
        logger.log("Testing API key for provider: \(provider)", level: .info)
        return await aiManager.testAPIKey(apiKey: apiKey)
    }
    
    /// Get debug information for the current configuration
    func getDebugInfo() -> String {
        """
        Current Configuration:
        - Provider: \(settings.selectedProvider)
        - Model: \(settings.transcriptionModel)
        - Language: \(settings.transcriptionLanguage)
        - Temperature: \(settings.transcriptionTemperature)
        - API Key Set: \(!settings.getCurrentAPIKey().isEmpty)
        - Microphone: \(settings.selectedMicrophoneID)
        """
    }
}

/// Custom errors for transcription operations
enum TranscriptionError: LocalizedError {
    case fileNotFound
    case noAPIKey(provider: String)
    case invalidConfiguration
    
    var errorDescription: String? {
        switch self {
        case .fileNotFound:
            return "Audio file not found"
        case .noAPIKey(let provider):
            return "No API key configured for \(provider)"
        case .invalidConfiguration:
            return "Invalid transcription configuration"
        }
    }
}

/// Extension to handle clipboard operations
extension TranscriptionService {
    /// Copy transcription to clipboard and optionally paste
    func handleTranscriptionResult(_ text: String, autoPaste: Bool = false) {
        logger.log("Copying transcription to clipboard", level: .info)
        NSPasteboard.general.clearContents()
        let success = NSPasteboard.general.setString(text, forType: .string)
        logger.log("Clipboard setString result: \(success)", level: .info)
        
        // Verify clipboard content
        if let clipboardCheck = NSPasteboard.general.string(forType: .string) {
            logger.log("Verified clipboard content (first 50 chars): \(String(clipboardCheck.prefix(50)))...", level: .info)
        } else {
            logger.log("ERROR: Failed to verify clipboard content!", level: .error)
        }
        
        if autoPaste && settings.autoPasteTranscription {
            logger.log("Auto-paste is enabled, will paste after closing popup", level: .info)
        }
    }
}