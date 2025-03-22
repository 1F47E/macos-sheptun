import SwiftUI

struct SettingsView: View {
    @StateObject private var settings = SettingsManager.shared
    @State private var apiKeyInput: String = ""
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
            
            // API Key Section
            VStack(alignment: .leading, spacing: 12) {
                Text("OpenAI API Key")
                    .font(.headline)
                    .foregroundColor(.primary)
                
                TextField("Enter your OpenAI API key", text: $apiKeyInput)
                    .font(.system(size: 16))
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .padding(.vertical, 4)
                    .onChange(of: apiKeyInput) { newValue in
                        logger.log("API key input changed")
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
        .frame(width: 500, height: 350)
        .onAppear {
            logger.log("Settings view appeared")
            apiKeyInput = settings.openAIKey
            logger.log("API key loaded from settings: \(settings.maskAPIKey(apiKeyInput))")
        }
    }
} 