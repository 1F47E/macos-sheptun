import SwiftUI
import AVFoundation

struct SettingsView: View {
    @StateObject private var settings = SettingsManager.shared
    
    // Keep track of whether we’re revealing each API key
    @State private var showOpenAIKey: Bool = false
    @State private var showGroqKey: Bool = false
    
    // Local copies of the keys (we mirror them from settings)
    @State private var openAIKeyInput: String = ""
    @State private var groqKeyInput: String = ""
    
    // Microphone
    @State private var availableMicrophones: [SettingsManager.MicrophoneDevice] = []
    @State private var audioLevel: Float = 0
    @State private var audioMonitor: AudioLevelMonitor? = nil
    @State private var audioMonitorError: String? = nil
    
    // Testing API key
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
        VStack {
            
            ScrollView {
                Form {
                    // PROVIDER PICKER
                    Section {
                        Picker("Provider", selection: $settings.selectedProvider) {
                            Text("OpenAI").tag("openai")
                            Text("Groq").tag("groq")
                            // If you add new providers later, add them here
                        }
                        .pickerStyle(SegmentedPickerStyle())
                        .onChange(of: settings.selectedProvider) { _ in
                            settings.updateModelForProvider()
                            settings.saveSettings()
                        }
                    } header: {
                        Text("Provider")
                    }
                    
                    // CREDENTIALS SECTION (OpenAI or Groq)
                    Section {
                        if settings.selectedProvider == "openai" {
                            // Eye toggle example for OpenAI
                            HStack {
                                if showOpenAIKey {
                                    TextField("OpenAI API Key", text: $openAIKeyInput)
                                        .textFieldStyle(RoundedBorderTextFieldStyle())
                                } else {
                                    SecureField("OpenAI API Key", text: $openAIKeyInput)
                                        .textFieldStyle(RoundedBorderTextFieldStyle())
                                }
                                Button(action: {
                                    showOpenAIKey.toggle()
                                }) {
                                    Image(systemName: showOpenAIKey ? "eye.slash.fill" : "eye.fill")
                                        .foregroundColor(.gray)
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                            .onAppear {
                                openAIKeyInput = settings.openAIKey
                            }
                            .onChange(of: openAIKeyInput) { newValue in
                                settings.openAIKey = newValue
                                settings.saveSettings()
                            }
                            
                        } else if settings.selectedProvider == "groq" {
                            HStack {
                                if showGroqKey {
                                    TextField("", text: $groqKeyInput)
                                        .textFieldStyle(RoundedBorderTextFieldStyle())
                                } else {
                                    SecureField("", text: $groqKeyInput)
                                        .textFieldStyle(RoundedBorderTextFieldStyle())
                                }
                                Button(action: {
                                    showGroqKey.toggle()
                                }) {
                                    Image(systemName: showGroqKey ? "eye.slash.fill" : "eye.fill")
                                        .foregroundColor(.gray)
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                            .onAppear {
                                groqKeyInput = settings.groqKey
                            }
                            .onChange(of: groqKeyInput) { newValue in
                                settings.groqKey = newValue
                                settings.saveSettings()
                            }
                        }

                                   // TEST API KEY
                    if !currentAPIKey().isEmpty {
                        Section {
                            HStack {
                                Button("Test API Key") {
                                    apiKeyTestResult = nil
                                    testAPIKey()
                                }
                                .disabled(isTestingAPIKey)
                                
                                if isTestingAPIKey {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle())
                                } else if let result = apiKeyTestResult {
                                    switch result {
                                    case .success:
                                        Label("API Key is valid", systemImage: "checkmark.circle.fill")
                                            .foregroundColor(.green)
                                    case .error(let msg):
                                        Label("Invalid API Key: \(msg)", systemImage: "xmark.circle.fill")
                                            .foregroundColor(.red)
                                    case .networkError(let msg):
                                        Label("Network error: \(msg)", systemImage: "wifi.slash")
                                            .foregroundColor(.orange)
                                    }
                                }
                            }
                        }
                    }

                    } header: {
                        Text("API Key")
                        .padding(.top, 20)
                    }
                    
                    // MODEL & TEMPERATURE
                    Section {
                        if settings.selectedProvider == "openai" {
                            Picker("Model", selection: $settings.transcriptionModel) {
                                Text("GPT-4o Mini").tag("gpt-4o-mini-transcribe")
                                Text("GPT-4o").tag("gpt-4o-transcribe")
                                Text("Whisper").tag("whisper-1")
                            }
                            .pickerStyle(.segmented)
                            .onChange(of: settings.transcriptionModel) { _ in
                                settings.saveSettings()
                            }
                        } else {
                            Picker("Model", selection: $settings.transcriptionModel) {
                                Text("Whisper Large v3").tag("whisper-large-v3")
                                Text("Whisper Large v3 Turbo").tag("whisper-large-v3-turbo")
                            }
                            .pickerStyle(.segmented)
                            .onChange(of: settings.transcriptionModel) { _ in
                                settings.saveSettings()
                            }
                        }
                        
                        // Temperature slider
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Temperature: \(settings.transcriptionTemperature, specifier: "%.2f")")
                            Slider(value: $settings.transcriptionTemperature, in: 0.0...1.0, step: 0.05) { _ in
                                settings.saveSettings()
                            }
                            Text("Lower = more accurate, Higher = more creative")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.top, 8)


                        
                    } header: {
                        Text("Model & Temperature")
                        .padding(.top, 20)
                    }
                    
                    // MICROPHONE SELECTION
                    Section {
                        if availableMicrophones.isEmpty {
                            Text("No microphones found.")
                                .foregroundColor(.red)
                        } else {
                            Picker("Input Device", selection: $settings.selectedMicrophoneID) {
                                ForEach(availableMicrophones) { mic in
                                    Text(mic.name).tag(mic.id)
                                }
                            }
                            .onChange(of: settings.selectedMicrophoneID) { newID in
                                settings.saveSettings()
                                if !newID.isEmpty {
                                    startAudioMonitoring(deviceID: newID)
                                } else {
                                    stopAudioMonitoring()
                                }
                            }
                            
                            // Audio level meter (horizontal bars)
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Microphone Level")
                                    .font(.subheadline)
                                HStack(spacing: 2) {
                                    ForEach(0..<20, id: \.self) { index in
                                        Rectangle()
                                            .fill(barColor(for: index))
                                            .frame(width: 4) // narrower bars
                                    }
                                }
                                .frame(height: 16)
                                
                                if let error = audioMonitorError {
                                    Text("Error: \(error)")
                                        .foregroundColor(.red)
                                        .font(.caption)
                                }
                            }
                            .padding(.vertical, 6)
                        }
                    } header: {
                        Text("Microphone")
                        .padding(.top, 20)
                    }
                    
         
                }
                .padding(.horizontal, 12)
            }
            
        }
        .frame(minWidth: 540, minHeight: 520)
        .onAppear {
            loadMicrophones()
            if !settings.selectedMicrophoneID.isEmpty {
                startAudioMonitoring(deviceID: settings.selectedMicrophoneID)
            }
            
            // Mirror keys to local state
            openAIKeyInput = settings.openAIKey
            groqKeyInput = settings.groqKey
        }
        .onDisappear {
            stopAudioMonitoring()
            apiTestTask?.cancel()
        }
    }
    
    // MARK: - Helper Methods
    
    private func currentAPIKey() -> String {
        switch settings.selectedProvider {
        case "openai": return settings.openAIKey
        case "groq":   return settings.groqKey
        default:       return ""
        }
    }
    
    private func barColor(for index: Int) -> Color {
        let threshold = Float(index) / 20.0
        if audioLevel >= threshold {
            if index < 7 {
                return .green
            } else if index < 15 {
                return .yellow
            } else {
                return .red
            }
        } else {
            return Color.gray.opacity(0.3)
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
            
            do {
                let isValid = await aiManager.testAPIKey(apiKey: key)
                if Task.isCancelled { return }
                
                DispatchQueue.main.async {
                    if isValid {
                        apiKeyTestResult = .success
                    } else {
                        apiKeyTestResult = .error("Invalid key or insufficient permissions")
                    }
                }
            } catch {
                if Task.isCancelled { return }
                DispatchQueue.main.async {
                    apiKeyTestResult = .networkError(error.localizedDescription)
                }
            }
        }
    }
    
    private func loadMicrophones() {
        availableMicrophones = settings.getAvailableMicrophones()
        logger.log("Loaded \(availableMicrophones.count) microphones")
        
        // If no mic selected but we have a system default, choose that
        if settings.selectedMicrophoneID.isEmpty && !availableMicrophones.isEmpty {
            if let defaultID = settings.getDefaultSystemMicrophoneID(),
               availableMicrophones.contains(where: { $0.id == defaultID }) {
                settings.selectedMicrophoneID = defaultID
            } else {
                // fallback to first
                settings.selectedMicrophoneID = availableMicrophones[0].id
            }
        }
    }
    
    private func startAudioMonitoring(deviceID: String) {
        stopAudioMonitoring()
        
        if let numericID = UInt32(deviceID) {
            audioMonitor = AudioLevelMonitor(deviceID: numericID)
            audioMonitor?.startMonitoring(
                levelUpdateHandler: { level in
                    DispatchQueue.main.async {
                        self.audioLevel = level
                        self.audioMonitorError = nil
                    }
                },
                errorHandler: { error in
                    DispatchQueue.main.async {
                        self.audioMonitorError = error
                        self.audioLevel = 0
                    }
                }
            )
        } else {
            audioMonitorError = "Invalid device ID format"
        }
    }
    
    private func stopAudioMonitoring() {
        audioMonitor?.stopMonitoring()
        audioMonitor = nil
    }
}
