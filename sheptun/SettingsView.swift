import SwiftUI

struct SettingsView: View {
    @StateObject private var settings = SettingsManager.shared
    @State private var isAPIKeyVisible = false
    @State private var apiKeyInput: String = ""
    @Environment(\.dismiss) private var dismiss
    private let logger = Logger.shared
    
    var body: some View {
        Form {
            Section("Hotkey") {
                HotkeyRecorder(keyCode: $settings.hotkeyKeyCode,
                             modifiers: $settings.hotkeyModifiers)
            }
            
            Section("OpenAI API Key") {
                HStack {
                    if isAPIKeyVisible {
                        TextField("API Key", text: $apiKeyInput)
                            .onChange(of: apiKeyInput) { newValue in
                                logger.log("API key input changed")
                            }
                    } else {
                        Text(settings.maskAPIKey(apiKeyInput))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .foregroundColor(apiKeyInput.isEmpty ? .secondary : .primary)
                    }
                    
                    Button {
                        isAPIKeyVisible.toggle()
                        logger.log("API key visibility toggled: \(isAPIKeyVisible ? "visible" : "hidden")")
                    } label: {
                        Image(systemName: isAPIKeyVisible ? "eye.slash" : "eye")
                    }
                    .buttonStyle(.borderless)
                }
            }
            
            HStack {
                Spacer()
                Button("Save") {
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
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(width: 400, height: 200)
        .onAppear {
            logger.log("Settings view appeared")
            apiKeyInput = settings.openAIKey
            logger.log("API key loaded from settings: \(settings.maskAPIKey(apiKeyInput))")
        }
    }
} 