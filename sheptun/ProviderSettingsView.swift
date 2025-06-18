import SwiftUI

struct ProviderSettingsView: View {
    @StateObject private var settings = SettingsManager.shared
    @State private var showOpenAIKey = false
    @State private var showGroqKey = false
    @State private var showDeepgramKey = false
    @State private var openAIKeyInput = ""
    @State private var groqKeyInput = ""
    @State private var deepgramKeyInput = ""
    @State private var isTestingAPIKey = false
    @State private var apiKeyTestResult: APIKeyTestResult?
    @State private var apiTestTask: Task<Void, Never>? = nil
    
    private let logger = Logger.shared
    
    enum APIKeyTestResult {
        case success
        case error(String)
        case networkError(String)
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                providerSelectionSection
                
                apiCredentialsSection
                
                modelConfigurationSection
            }
            .padding(24)
        }
        .onAppear {
            openAIKeyInput = settings.openAIKey
            groqKeyInput = settings.groqKey
            deepgramKeyInput = settings.deepgramKey
        }
        .onDisappear {
            apiTestTask?.cancel()
        }
    }
    
    private var providerSelectionSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("AI Provider")
                .font(.headline)
            
            HStack(spacing: 12) {
                ProviderCard(
                    name: "OpenAI",
                    icon: "network",
                    color: .green,
                    isSelected: settings.selectedProvider == "openai",
                    status: providerStatus(for: "openai"),
                    action: {
                        settings.selectedProvider = "openai"
                        settings.updateModelForProvider()
                        apiKeyTestResult = nil
                        settings.saveSettings()
                    }
                )
                
                ProviderCard(
                    name: "Groq",
                    icon: "bolt.circle",
                    color: .orange,
                    isSelected: settings.selectedProvider == "groq",
                    status: providerStatus(for: "groq"),
                    action: {
                        settings.selectedProvider = "groq"
                        settings.updateModelForProvider()
                        apiKeyTestResult = nil
                        settings.saveSettings()
                    }
                )
                
                ProviderCard(
                    name: "Deepgram",
                    icon: "waveform.circle",
                    color: .blue,
                    isSelected: settings.selectedProvider == "deepgram",
                    status: providerStatus(for: "deepgram"),
                    action: {
                        settings.selectedProvider = "deepgram"
                        settings.updateModelForProvider()
                        apiKeyTestResult = nil
                        settings.saveSettings()
                    }
                )
            }
        }
    }
    
    private var apiCredentialsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("API Credentials")
                    .font(.headline)
                
                Spacer()
                
                if let result = apiKeyTestResult {
                    statusIndicator(for: result)
                }
            }
            
            GroupBox {
                VStack(spacing: 12) {
                    if settings.selectedProvider == "openai" {
                        apiKeyField(
                            label: "OpenAI API Key",
                            keyInput: $openAIKeyInput,
                            showKey: $showOpenAIKey,
                            placeholder: "sk-...",
                            saveAction: { newValue in
                                settings.openAIKey = newValue
                                settings.saveSettings()
                            }
                        )
                    } else if settings.selectedProvider == "groq" {
                        apiKeyField(
                            label: "Groq API Key",
                            keyInput: $groqKeyInput,
                            showKey: $showGroqKey,
                            placeholder: "gsk_...",
                            saveAction: { newValue in
                                settings.groqKey = newValue
                                settings.saveSettings()
                            }
                        )
                    } else if settings.selectedProvider == "deepgram" {
                        apiKeyField(
                            label: "Deepgram API Key",
                            keyInput: $deepgramKeyInput,
                            showKey: $showDeepgramKey,
                            placeholder: "API Key",
                            saveAction: { newValue in
                                settings.deepgramKey = newValue
                                settings.saveSettings()
                            }
                        )
                    }
                }
                .padding(12)
            }
        }
    }
    
    private var modelConfigurationSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Model Configuration")
                .font(.headline)
            
            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Model")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    Picker("", selection: $settings.transcriptionModel) {
                        if settings.selectedProvider == "openai" {
                            Text("GPT-4o Mini").tag("gpt-4o-mini-transcribe")
                            Text("GPT-4o").tag("gpt-4o-transcribe")
                            Text("Whisper").tag("whisper-1")
                        } else if settings.selectedProvider == "groq" {
                            Text("Whisper Large v3").tag("whisper-large-v3")
                            Text("Whisper Large v3 Turbo").tag("whisper-large-v3-turbo")
                        } else if settings.selectedProvider == "deepgram" {
                            Text("Nova 3").tag("nova-3")
                            Text("Nova 2").tag("nova-2")
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .onChange(of: settings.transcriptionModel) { _, _ in
                        settings.saveSettings()
                    }
                }
                .padding(12)
            }
        }
    }
    
    @ViewBuilder
    private func apiKeyField(
        label: String,
        keyInput: Binding<String>,
        showKey: Binding<Bool>,
        placeholder: String,
        saveAction: @escaping (String) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            HStack {
                Group {
                    if showKey.wrappedValue {
                        TextField(placeholder, text: keyInput)
                    } else {
                        SecureField(placeholder, text: keyInput)
                    }
                }
                .textFieldStyle(.roundedBorder)
                
                Button(action: { showKey.wrappedValue.toggle() }) {
                    Image(systemName: showKey.wrappedValue ? "eye.slash" : "eye")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                
                if !keyInput.wrappedValue.isEmpty {
                    Button(action: testAPIKey) {
                        if isTestingAPIKey {
                            ProgressView()
                                .scaleEffect(0.7)
                                .frame(width: 60)
                        } else {
                            Text("Test Key")
                                .font(.caption)
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(isTestingAPIKey || keyInput.wrappedValue.isEmpty)
                }
            }
            .onChange(of: keyInput.wrappedValue) { _, newValue in
                saveAction(newValue)
                apiKeyTestResult = nil
            }
        }
    }
    
    @ViewBuilder
    private func statusIndicator(for result: APIKeyTestResult) -> some View {
        switch result {
        case .success:
            Label("Connected", systemImage: "checkmark.circle.fill")
                .foregroundColor(.green)
                .font(.caption)
        case .error(let msg):
            Label("Invalid", systemImage: "xmark.circle.fill")
                .foregroundColor(.red)
                .font(.caption)
                .help(msg)
        case .networkError(let msg):
            Label("Network Error", systemImage: "wifi.slash")
                .foregroundColor(.orange)
                .font(.caption)
                .help(msg)
        }
    }
    
    private func providerStatus(for provider: String) -> ProviderCard.Status {
        guard settings.selectedProvider == provider else { return .inactive }
        
        let hasKey = switch provider {
        case "openai": !settings.openAIKey.isEmpty
        case "groq": !settings.groqKey.isEmpty
        case "deepgram": !settings.deepgramKey.isEmpty
        default: false
        }
        
        if !hasKey { return .noKey }
        
        if let result = apiKeyTestResult {
            switch result {
            case .success: return .connected
            case .error: return .error
            case .networkError: return .error
            }
        }
        
        return .ready
    }
    
    private func currentAPIKey() -> String {
        switch settings.selectedProvider {
        case "openai": return settings.openAIKey
        case "groq": return settings.groqKey
        case "deepgram": return settings.deepgramKey
        default: return ""
        }
    }
    
    private func testAPIKey() {
        guard !isTestingAPIKey else { return }
        isTestingAPIKey = true
        apiKeyTestResult = nil
        
        apiTestTask?.cancel()
        apiTestTask = Task {
            defer {
                DispatchQueue.main.async {
                    isTestingAPIKey = false
                }
            }
            
            let key = currentAPIKey()
            if key.isEmpty {
                DispatchQueue.main.async {
                    apiKeyTestResult = .error("API Key is empty")
                }
                return
            }
            
            let provider = settings.getCurrentAIProvider()
            let aiManager = AIProviderFactory.getProvider(type: provider)
            
            let isValid = await aiManager.testAPIKey(apiKey: key)
            if Task.isCancelled { return }
            
            DispatchQueue.main.async {
                if isValid {
                    apiKeyTestResult = .success
                } else {
                    apiKeyTestResult = .error("Invalid key or connection issue")
                }
            }
        }
    }
}

struct ProviderCard: View {
    let name: String
    let icon: String
    let color: Color
    let isSelected: Bool
    let status: Status
    let action: () -> Void
    
    enum Status {
        case inactive, noKey, ready, connected, error
        
        var indicator: (icon: String, color: Color)? {
            switch self {
            case .inactive: return nil
            case .noKey: return ("key.slash", .gray)
            case .ready: return ("circle.fill", .yellow)
            case .connected: return ("checkmark.circle.fill", .green)
            case .error: return ("exclamationmark.triangle.fill", .red)
            }
        }
    }
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 12) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: icon)
                        .font(.system(size: 32))
                        .foregroundColor(isSelected ? color : .secondary)
                    
                    if let indicator = status.indicator {
                        Image(systemName: indicator.icon)
                            .font(.system(size: 12))
                            .foregroundColor(indicator.color)
                            .background(
                                Circle()
                                    .fill(Color(NSColor.controlBackgroundColor))
                                    .frame(width: 16, height: 16)
                            )
                            .offset(x: 8, y: -8)
                    }
                }
                
                Text(name)
                    .font(.system(.body, design: .rounded))
                    .fontWeight(isSelected ? .medium : .regular)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? color.opacity(0.1) : Color(NSColor.controlColor))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(
                                isSelected ? color : Color.clear,
                                lineWidth: 2
                            )
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    ProviderSettingsView()
        .frame(width: 600, height: 500)
}