import SwiftUI

struct SettingsView: View {
    @StateObject private var settings = SettingsManager.shared
    @State private var apiKeyInput: String = ""
    @State private var availableMicrophones: [SettingsManager.MicrophoneDevice] = []
    @Environment(\.dismiss) private var dismiss
    private let logger = Logger.shared
    
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
                
                HStack {
                    if apiKeyInput.isEmpty {
                        TextField("Enter your OpenAI API key", text: $apiKeyInput)
                            .font(.system(size: 16))
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .padding(.vertical, 4)
                            .onChange(of: apiKeyInput) { oldValue, newValue in
                                logger.log("API key input changed")
                            }
                    } else {
                        Text(maskAPIKey(apiKeyInput))
                            .font(.system(size: 16))
                            .padding(.vertical, 8)
                            .padding(.horizontal, 12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(.textBackgroundColor))
                            .cornerRadius(6)
                            .onTapGesture {
                                // Allow editing when tapped
                                // The field remains masked until saved and reopened
                            }
                    }
                    
                    Button {
                        logger.log("Test button pressed")
                        // Functionality to be added later
                    } label: {
                        Text("Test")
                            .font(.system(size: 14))
                    }
                    .buttonStyle(.bordered)
                    .disabled(apiKeyInput.isEmpty)
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
        .frame(width: 500, height: 400) // Increased height to accommodate the new section
        .onAppear {
            logger.log("Settings view appeared")
            apiKeyInput = settings.openAIKey
            logger.log("API key loaded from settings: \(settings.maskAPIKey(apiKeyInput))")
            
            // Load available microphones
            availableMicrophones = settings.getAvailableMicrophones()
            logger.log("Loaded \(availableMicrophones.count) microphones")
            
            // If no microphone is selected and we have microphones, select the first one
            if settings.selectedMicrophoneID.isEmpty && !availableMicrophones.isEmpty {
                settings.selectedMicrophoneID = availableMicrophones[0].id
                logger.log("Auto-selected first microphone: \(availableMicrophones[0].name)")
            }
        }
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
} 