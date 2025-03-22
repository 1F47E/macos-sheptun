import Foundation
import CryptoKit

class SettingsManager: ObservableObject {
    static let shared = SettingsManager()
    private let defaults = UserDefaults.standard
    private let encryptionKey = "YourRandomEncryptionKey123!@#$%^&*()"
    private let logger = Logger.shared
    
    @Published var hotkeyModifiers: UInt = 0
    @Published var hotkeyKeyCode: UInt = 0
    @Published var openAIKey: String = ""
    
    private enum Keys {
        static let hotkeyModifiers = "hotkeyModifiers"
        static let hotkeyKeyCode = "hotkeyKeyCode"
        static let openAIKey = "openAIKey"
    }
    
    init() {
        logger.log("SettingsManager initialized", level: .info)
        loadSettings()
    }
    
    private func loadSettings() {
        logger.log("Loading settings from UserDefaults")
        
        hotkeyModifiers = UInt(defaults.integer(forKey: Keys.hotkeyModifiers))
        hotkeyKeyCode = UInt(defaults.integer(forKey: Keys.hotkeyKeyCode))
        
        logger.log("Loaded hotkey: modifiers=\(hotkeyModifiers), keyCode=\(hotkeyKeyCode)")
        
        if let encryptedKey = defaults.string(forKey: Keys.openAIKey) {
            logger.log("Found encrypted API key, attempting to decrypt")
            openAIKey = decryptString(encryptedKey) ?? ""
            
            if openAIKey.isEmpty {
                logger.log("Failed to decrypt API key", level: .error)
            } else {
                logger.log("Successfully decrypted API key: \(maskAPIKey(openAIKey))")
            }
            
            print("DEBUG: Loaded API key - \(maskAPIKey(openAIKey))")
        } else {
            logger.log("No API key found in settings", level: .info)
        }
    }
    
    func saveSettings() {
        logger.log("Saving settings to UserDefaults")
        
        defaults.set(hotkeyModifiers, forKey: Keys.hotkeyModifiers)
        defaults.set(hotkeyKeyCode, forKey: Keys.hotkeyKeyCode)
        
        logger.log("Saved hotkey: modifiers=\(hotkeyModifiers), keyCode=\(hotkeyKeyCode)")
        
        if !openAIKey.isEmpty {
            logger.log("Encrypting and saving API key")
            defaults.set(encryptString(openAIKey), forKey: Keys.openAIKey)
            print("DEBUG: Saved API key - \(maskAPIKey(openAIKey))")
            logger.log("API key saved: \(maskAPIKey(openAIKey))")
        } else {
            logger.log("No API key to save", level: .warning)
        }
    }
    
    func maskAPIKey(_ key: String) -> String {
        guard key.count > 10 else { return key.isEmpty ? "Not set" : "***" }
        
        let prefix = String(key.prefix(5))
        let suffix = String(key.suffix(5))
        return "\(prefix)•••••\(suffix)"
    }
    
    private func encryptString(_ string: String) -> String {
        logger.log("Encrypting string using AES-GCM")
        
        guard let data = string.data(using: .utf8),
              let keyData = encryptionKey.data(using: .utf8) else { 
            logger.log("Failed to prepare data for encryption", level: .error)
            return "" 
        }
        
        let key = SymmetricKey(data: SHA256.hash(data: keyData))
        
        do {
            let sealedBox = try AES.GCM.seal(data, using: key)
            guard let combined = sealedBox.combined?.base64EncodedString() else {
                logger.log("Failed to get combined data after encryption", level: .error)
                return ""
            }
            logger.log("String encrypted successfully")
            return combined
        } catch {
            logger.log("Encryption error: \(error)", level: .error)
            print("Encryption error: \(error)")
            return ""
        }
    }
    
    private func decryptString(_ encrypted: String) -> String? {
        logger.log("Decrypting string using AES-GCM")
        
        guard let data = Data(base64Encoded: encrypted),
              let keyData = encryptionKey.data(using: .utf8) else { 
            logger.log("Failed to prepare data for decryption", level: .error)
            return nil 
        }
        
        let key = SymmetricKey(data: SHA256.hash(data: keyData))
        
        do {
            let sealedBox = try AES.GCM.SealedBox(combined: data)
            let decryptedData = try AES.GCM.open(sealedBox, using: key)
            logger.log("String decrypted successfully")
            return String(data: decryptedData, encoding: .utf8)
        } catch {
            logger.log("Decryption error: \(error)", level: .error)
            print("Decryption error: \(error)")
            return nil
        }
    }
} 