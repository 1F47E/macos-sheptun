import Foundation
import CryptoKit
import CoreAudio

class SettingsManager: ObservableObject {
    static let shared = SettingsManager()
    private let defaults = UserDefaults.standard
    private let encryptionKey = "YourRandomEncryptionKey123!@#$%^&*()"
    private let logger = Logger.shared
    
    @Published var hotkeyModifiers: UInt = 0
    @Published var hotkeyKeyCode: UInt = 0
    @Published var openAIKey: String = ""
    @Published var groqKey: String = ""
    @Published var selectedMicrophoneID: String = ""
    @Published var transcriptionModel: String = "whisper-large-v3-turbo"
    @Published var transcriptionTemperature: Double = 0.3
    @Published var selectedProvider: String = "groq"
    @Published var isRecordingAudio = false
    @Published var lastError: String?
    
    private enum Keys {
        static let hotkeyModifiers = "hotkeyModifiers"
        static let hotkeyKeyCode = "hotkeyKeyCode"
        static let openAIKey = "openAIKey"
        static let groqKey = "groqKey"
        static let selectedMicrophoneID = "selectedMicrophoneID"
        static let transcriptionModel = "transcriptionModel"
        static let transcriptionTemperature = "transcriptionTemperature"
        static let selectedProvider = "selectedProvider"
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
            logger.log("Found encrypted OpenAI API key, attempting to decrypt")
            openAIKey = decryptString(encryptedKey) ?? ""
            
            if openAIKey.isEmpty {
                logger.log("Failed to decrypt OpenAI API key", level: .error)
            } else {
                logger.log("Successfully decrypted OpenAI API key: \(maskAPIKey(openAIKey))")
            }
            
            print("DEBUG: Loaded OpenAI API key - \(maskAPIKey(openAIKey))")
        } else {
            logger.log("No OpenAI API key found in settings", level: .info)
        }
        
        if let encryptedKey = defaults.string(forKey: Keys.groqKey) {
            logger.log("Found encrypted Groq API key, attempting to decrypt")
            groqKey = decryptString(encryptedKey) ?? ""
            
            if groqKey.isEmpty {
                logger.log("Failed to decrypt Groq API key", level: .error)
            } else {
                logger.log("Successfully decrypted Groq API key: \(maskAPIKey(groqKey))")
            }
            
            print("DEBUG: Loaded Groq API key - \(maskAPIKey(groqKey))")
        } else {
            logger.log("No Groq API key found in settings", level: .info)
        }
        
        if let provider = defaults.string(forKey: Keys.selectedProvider) {
            selectedProvider = provider
            logger.log("Loaded selected provider: \(provider)")
        } else {
            selectedProvider = "groq" // Default to Groq when first opened
            logger.log("No provider selected, defaulting to Groq", level: .info)
        }
        
        if let savedMicID = defaults.string(forKey: Keys.selectedMicrophoneID) {
            selectedMicrophoneID = savedMicID
            logger.log("Loaded saved microphone ID: \(savedMicID)")
        } else {
            // Try to get the system default microphone
            if let defaultMicID = getDefaultSystemMicrophoneID() {
                selectedMicrophoneID = defaultMicID
                logger.log("No saved microphone, using system default: \(defaultMicID)")
            } else if let firstMic = getAvailableMicrophones().first {
                // Fall back to first available if we can't get the system default
                selectedMicrophoneID = firstMic.id
                logger.log("No system default, using first available: \(firstMic.name)")
            } else {
                logger.log("No microphones available", level: .warning)
            }
        }
        
        if let savedModel = defaults.string(forKey: Keys.transcriptionModel) {
            transcriptionModel = savedModel
            logger.log("Loaded transcription model: \(savedModel)")
        } else {
            // Set default model based on the selected provider
            if selectedProvider == "openai" {
                transcriptionModel = "gpt-4o-mini-transcribe"
            } else {
                transcriptionModel = "whisper-large-v3-turbo"
            }
            logger.log("Using default transcription model: \(transcriptionModel)")
        }
        
        // Load temperature or use default
        transcriptionTemperature = defaults.double(forKey: Keys.transcriptionTemperature)
        if transcriptionTemperature == 0.0 {
            transcriptionTemperature = 0.3 // Default if not set
        }
        logger.log("Loaded transcription temperature: \(transcriptionTemperature)")
    }
    
    // Method to get the default model for the current provider
    func getDefaultModelForProvider(provider: String) -> String {
        switch provider.lowercased() {
        case "groq":
            return "whisper-large-v3-turbo"
        case "openai":
            return "gpt-4o-mini-transcribe"
        default:
            return "gpt-4o-mini-transcribe"
        }
    }
    
    // Call this when provider changes to update the model appropriately
    func updateModelForProvider() {
        let previousModel = transcriptionModel
        
        // Only update the model if it's not already set for the current provider
        // or if switching providers
        if (selectedProvider == "openai" && !["gpt-4o-mini-transcribe", "gpt-4o-transcribe", "whisper-1"].contains(transcriptionModel)) ||
           (selectedProvider == "groq" && !["whisper-large-v3", "whisper-large-v3-turbo"].contains(transcriptionModel)) {
            
            transcriptionModel = getDefaultModelForProvider(provider: selectedProvider)
            logger.log("Provider changed to \(selectedProvider), updated model from \(previousModel) to \(transcriptionModel)")
        }
    }
    
    func saveSettings() {
        logger.log("Saving settings to UserDefaults")
        
        defaults.set(hotkeyModifiers, forKey: Keys.hotkeyModifiers)
        defaults.set(hotkeyKeyCode, forKey: Keys.hotkeyKeyCode)
        
        logger.log("Saved hotkey: modifiers=\(hotkeyModifiers), keyCode=\(hotkeyKeyCode)")
        
        if !openAIKey.isEmpty {
            logger.log("Encrypting and saving OpenAI API key")
            defaults.set(encryptString(openAIKey), forKey: Keys.openAIKey)
            print("DEBUG: Saved OpenAI API key - \(maskAPIKey(openAIKey))")
            logger.log("OpenAI API key saved: \(maskAPIKey(openAIKey))")
        } else {
            logger.log("No OpenAI API key to save", level: .warning)
        }
        
        if !groqKey.isEmpty {
            logger.log("Encrypting and saving Groq API key")
            defaults.set(encryptString(groqKey), forKey: Keys.groqKey)
            print("DEBUG: Saved Groq API key - \(maskAPIKey(groqKey))")
            logger.log("Groq API key saved: \(maskAPIKey(groqKey))")
        } else {
            logger.log("No Groq API key to save", level: .warning)
        }
        
        defaults.set(selectedProvider, forKey: Keys.selectedProvider)
        logger.log("Saved selected provider: \(selectedProvider)")
        
        defaults.set(selectedMicrophoneID, forKey: Keys.selectedMicrophoneID)
        logger.log("Saved microphone ID: \(selectedMicrophoneID)")
        
        defaults.set(transcriptionModel, forKey: Keys.transcriptionModel)
        logger.log("Saved transcription model: \(transcriptionModel)")
        
        defaults.set(transcriptionTemperature, forKey: Keys.transcriptionTemperature)
        logger.log("Saved transcription temperature: \(transcriptionTemperature)")
    }
    
    // Returns the current selected AIProviderType
    func getCurrentAIProvider() -> AIProviderType {
        switch selectedProvider.lowercased() {
        case "groq":
            return .groq
        default:
            return .openAI
        }
    }
    
    // Returns the appropriate API key for the current provider
    func getCurrentAPIKey() -> String {
        switch getCurrentAIProvider() {
        case .groq:
            return groqKey
        case .openAI:
            return openAIKey
        }
    }
    
    struct MicrophoneDevice: Identifiable, Hashable {
        let id: String
        let name: String
        
        func hash(into hasher: inout Hasher) {
            hasher.combine(id)
        }
        
        static func == (lhs: MicrophoneDevice, rhs: MicrophoneDevice) -> Bool {
            return lhs.id == rhs.id
        }
    }
    
    func getAvailableMicrophones() -> [MicrophoneDevice] {
        var microphones: [MicrophoneDevice] = []
        
        // Get all audio devices in the system
        var propertySize: UInt32 = 0
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        // Get size of the array to be returned
        var status = AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &propertySize
        )
        
        if status != noErr {
            logger.log("Error getting audio device list size: \(status)", level: .error)
            return microphones
        }
        
        // Calculate the number of devices
        let deviceCount = Int(propertySize) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = [AudioDeviceID](repeating: 0, count: deviceCount)
        
        // Get the list of device IDs
        status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &propertySize,
            &deviceIDs
        )
        
        if status != noErr {
            logger.log("Error getting audio device list: \(status)", level: .error)
            return microphones
        }
        
        // For each device, check if it's an input device and get its name
        for deviceID in deviceIDs {
            // Check if the device does input
            var inputChannels: UInt32 = 0
            var inputScope = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyStreamConfiguration,
                mScope: kAudioDevicePropertyScopeInput,
                mElement: kAudioObjectPropertyElementMain
            )
            
            // Get the input stream configuration size
            var inputPropSize: UInt32 = 0
            status = AudioObjectGetPropertyDataSize(
                deviceID,
                &inputScope,
                0,
                nil,
                &inputPropSize
            )
            
            if status == noErr && inputPropSize > 0 {
                // Allocate buffer for the input stream configuration data
                let inputData = UnsafeMutablePointer<AudioBufferList>.allocate(capacity: Int(inputPropSize))
                defer { inputData.deallocate() }
                
                // Get the input stream configuration
                status = AudioObjectGetPropertyData(
                    deviceID,
                    &inputScope,
                    0,
                    nil,
                    &inputPropSize,
                    inputData
                )
                
                if status == noErr {
                    // Get number of input channels
                    let buffers = UnsafeMutableAudioBufferListPointer(inputData)
                    for buffer in buffers {
                        inputChannels += buffer.mNumberChannels
                    }
                }
            }
            
            // If the device has input channels, get its name
            if inputChannels > 0 {
                // Get device name
                var nameSize = UInt32(MemoryLayout<CFString>.size)
                var name: CFString? = nil
                var nameAddress = AudioObjectPropertyAddress(
                    mSelector: kAudioObjectPropertyName,
                    mScope: kAudioObjectPropertyScopeGlobal,
                    mElement: kAudioObjectPropertyElementMain
                )
                
                status = AudioObjectGetPropertyData(
                    deviceID,
                    &nameAddress,
                    0,
                    nil,
                    &nameSize,
                    &name
                )
                
                if status == noErr, let deviceName = name as String? {
                    let deviceIDString = String(deviceID)
                    microphones.append(MicrophoneDevice(id: deviceIDString, name: deviceName))
                    logger.log("Found microphone: \(deviceName) (ID: \(deviceIDString))")
                }
            }
        }
        
        return microphones
    }
    
    func maskAPIKey(_ key: String) -> String {
        guard !key.isEmpty else { return "Not set" }
        guard key.count > 2 else { return "•••" }
        
        // Only show first and last letter
        let first = String(key.prefix(1))
        let last = String(key.suffix(1))
        return "\(first)•••••\(last)"
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
    
    func getDefaultSystemMicrophoneID() -> String? {
        var deviceID: AudioDeviceID = 0
        var propertySize = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &propertySize,
            &deviceID
        )
        
        if status == noErr {
            logger.log("Default system microphone ID: \(deviceID)")
            return String(deviceID)
        } else {
            logger.log("Error getting default system microphone: \(status)", level: .error)
            return nil
        }
    }
}
