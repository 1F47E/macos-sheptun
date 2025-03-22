import SwiftUI

struct SettingsView: View {
    @StateObject private var settings = SettingsManager.shared
    @State private var apiKeyInput: String = ""
    @State private var availableMicrophones: [SettingsManager.MicrophoneDevice] = []
    @State private var isTestingAPIKey: Bool = false
    @State private var apiKeyTestResult: APIKeyTestResult?
    @State private var apiTestTask: Task<Void, Never>? = nil
    @Environment(\.dismiss) private var dismiss
    private let logger = Logger.shared
    
    enum APIKeyTestResult {
        case success
        case error(String)
        case networkError(String)
    }
    
    var body: some View {
        VStack(spacing: 24) {
            // Hotkey Section
            VStack(alignment: .leading, spacing: 12) {
                Text("Hotkey")
                    .font(.headline)
                    .foregroundColor(.primary)
                
                HotkeyRecorder(keyCode: $settings.hotkeyKeyCode,
                             modifiers: $settings.hotkeyModifiers)
                    .padding()
                    .background(Color(.controlBackgroundColor))
                    .cornerRadius(8)
            }
            .padding(.horizontal)
            
            // Microphone Selection Section
            VStack(alignment: .leading, spacing: 12) {
                Text("Microphone")
                    .font(.headline)
                    .foregroundColor(.primary)
                
                VStack {
                    if availableMicrophones.isEmpty {
                        Text("No microphones available")
                            .foregroundColor(.secondary)
                            .padding()
                    } else {
                        Picker("Select Microphone", selection: $settings.selectedMicrophoneID) {
                            ForEach(availableMicrophones) { mic in
                                Text(mic.name).tag(mic.id)
                            }
                        }
                        .labelsHidden()
                        .onChange(of: settings.selectedMicrophoneID) { oldValue, newValue in
                            logger.log("Selected microphone changed to ID: \(newValue)")
                        }
                    }
                }
                .padding()
                .background(Color(.controlBackgroundColor))
                .cornerRadius(8)
            }
            .padding(.horizontal)
            
            // API Key Section
            VStack(alignment: .leading, spacing: 12) {
                Text("OpenAI API Key")
                    .font(.headline)
                    .foregroundColor(.primary)
                
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        TextField("Enter your OpenAI API key", text: $apiKeyInput)
                            .font(.system(size: 16))
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .padding(.vertical, 4)
                            .onChange(of: apiKeyInput) { oldValue, newValue in
                                logger.log("API key input changed")
                                apiKeyTestResult = nil // Clear previous test result
                            }
                        
                        Button {
                            logger.log("Test button pressed")
                            testAPIKey()
                        } label: {
                            HStack(spacing: 4) {
                                if isTestingAPIKey {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle())
                                        .scaleEffect(0.7)
                                        .frame(width: 16, height: 16)
                                    Text("Testing")
                                        .font(.system(size: 14))
                                } else {
                                    Text("Test")
                                        .font(.system(size: 14))
                                }
                            }
                            .frame(minWidth: 70)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.bordered)
                        .disabled(apiKeyInput.isEmpty || isTestingAPIKey)
                    }
                    
                    // API Key test result
                    if let result = apiKeyTestResult {
                        HStack(spacing: 6) {
                            switch result {
                            case .success:
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                Text("API key is valid")
                                    .foregroundColor(.green)
                            case .networkError(let message):
                                Image(systemName: "wifi.exclamationmark")
                                    .foregroundColor(.orange)
                                Text("Network issue: \(message)")
                                    .foregroundColor(.orange)
                                    .font(.system(size: 14))
                            case .error(let message):
                                Image(systemName: "exclamationmark.circle.fill")
                                    .foregroundColor(.red)
                                Text(message)
                                    .foregroundColor(.red)
                                    .font(.system(size: 14))
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
                .padding()
                .background(Color(.controlBackgroundColor))
                .cornerRadius(8)
            }
            .padding(.horizontal)
            
            Spacer()
            
            // Save Button
            Button {
                logger.log("Save button pressed")
                if !apiKeyInput.isEmpty {
                    logger.log("Updating API key from input field")
                    settings.openAIKey = apiKeyInput
                } else {
                    logger.log("API key input is empty, not updating", level: .warning)
                }
                settings.saveSettings()
                logger.log("Settings saved, dismissing settings view")
                dismiss()
            } label: {
                Text("Save")
                    .font(.headline)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 16)
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
            .padding(.bottom, 20)
        }
        .frame(width: 500, height: 420) // Slightly increased for possible error message
        .onAppear {
            logger.log("Settings view appeared")
            apiKeyInput = settings.openAIKey
            logger.log("API key loaded from settings: \(settings.maskAPIKey(apiKeyInput))")
            
            // Load available microphones
            availableMicrophones = settings.getAvailableMicrophones()
            logger.log("Loaded \(availableMicrophones.count) microphones")
            
            // If no microphone is selected but we have a system default, use that
            if settings.selectedMicrophoneID.isEmpty && !availableMicrophones.isEmpty {
                if let defaultID = settings.getDefaultSystemMicrophoneID() {
                    // Check if the default microphone is in our list
                    if availableMicrophones.contains(where: { $0.id == defaultID }) {
                        settings.selectedMicrophoneID = defaultID
                        logger.log("Auto-selected system default microphone: \(defaultID)")
                    } else {
                        // Fall back to first available
                        settings.selectedMicrophoneID = availableMicrophones[0].id
                        logger.log("System default not available, selected first microphone: \(availableMicrophones[0].name)")
                    }
                } else {
                    // If no system default is available, select the first one
                    settings.selectedMicrophoneID = availableMicrophones[0].id
                    logger.log("No system default, auto-selected first microphone: \(availableMicrophones[0].name)")
                }
            }
        }
        .onDisappear {
            cleanup()
        }
    }
    
    private func testAPIKey() {
        logger.log("testAPIKey() method called", level: .debug)
        
        guard !apiKeyInput.isEmpty else {
            logger.log("Cannot test: API key is empty", level: .warning)
            return
        }
        
        logger.log("API key not empty, proceeding with test", level: .debug)
        isTestingAPIKey = true
        apiKeyTestResult = nil
        
        // Cancel any previous task
        apiTestTask?.cancel()
        
        logger.log("Creating async Task to test API key", level: .debug)
        apiTestTask = Task {
            logger.log("Inside async Task, about to call OpenAIManager.testAPIKey", level: .debug)
            let result = await OpenAIManager.shared.testAPIKey(apiKey: apiKeyInput)
            logger.log("Received result from OpenAIManager.testAPIKey", level: .debug)
            
            // Ensure we're not cancelled
            if !Task.isCancelled {
                // Switch back to the main thread to update UI
                await MainActor.run {
                    logger.log("Inside MainActor.run", level: .debug)
                    isTestingAPIKey = false
                    
                    switch result {
                    case .success:
                        logger.log("API key test successful", level: .info)
                        apiKeyTestResult = .success
                    case .failure(let error):
                        logger.log("API key test failed: \(error.localizedDescription)", level: .error)
                        
                        // Handle different types of errors with different UI feedback
                        switch error {
                        case OpenAIManager.APIError.networkConnectivity(let message):
                            apiKeyTestResult = .networkError(simplifyNetworkErrorMessage(message))
                        case OpenAIManager.APIError.invalidAPIKey:
                            apiKeyTestResult = .error("Invalid API key")
                        default:
                            apiKeyTestResult = .error(error.localizedDescription)
                        }
                    }
                }
            } else {
                logger.log("Task was cancelled", level: .warning)
            }
        }
        logger.log("Async Task created", level: .debug)
    }
    
    private func simplifyNetworkErrorMessage(_ message: String) -> String {
        // Extract the most relevant part of network error messages
        if message.contains("specified hostname could not be found") {
            return "Could not connect to OpenAI API"
        } else if message.contains("The Internet connection appears to be offline") {
            return "Internet connection is offline"
        } else if message.contains("timed out") {
            return "Connection timed out"
        }
        
        // Return a shorter version of the original message if it's too long
        let maxLength = 50
        if message.count > maxLength {
            return String(message.prefix(maxLength)) + "..."
        }
        
        return message
    }
    
    private func maskAPIKey(_ key: String) -> String {
        guard key.count > 8 else {
            return String(repeating: "*", count: key.count)
        }
        
        let prefix = String(key.prefix(4))
        let suffix = String(key.suffix(4))
        let stars = String(repeating: "*", count: 10)
        
        return prefix + stars + suffix
    }
    
    // Make sure to cancel the task when the view disappears
    private func cleanup() {
        apiTestTask?.cancel()
        apiTestTask = nil
    }
} 