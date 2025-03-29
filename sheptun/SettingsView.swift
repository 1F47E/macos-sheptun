import SwiftUI
import AVFoundation

struct SettingsView: View {
    @StateObject private var settings = SettingsManager.shared
    
    // Keep track of whether we're revealing each API key
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
        // Use a VStack for more control over layout and spacing
        VStack(alignment: .leading, spacing: 0) { // Use spacing 0 and manage padding manually
            ScrollView {
                // Group content logically with padding and dividers
                VStack(alignment: .leading, spacing: 15) { // Spacing between groups
                    
                    // --- Provider Selection Group ---
                    VStack(alignment: .leading, spacing: 8) {
                        Text("AI Provider")
                            .font(.title3) // Slightly larger heading for groups
                        Picker("Provider", selection: $settings.selectedProvider) {
                            Text("OpenAI").tag("openai")
                            Text("Groq").tag("groq")
                        }
                        .pickerStyle(SegmentedPickerStyle())
                        .labelsHidden() // Hide the Picker's label as the title is sufficient
                        .onChange(of: settings.selectedProvider) { oldValue, newValue in
                            settings.updateModelForProvider()
                            apiKeyTestResult = nil // Reset test result on provider change
                            settings.saveSettings()
                        }
                        Text("Select the transcription service provider.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.bottom, 10) // Add space before divider
                    
                    Divider()
                    
                    // --- API Credentials Group ---
                    VStack(alignment: .leading, spacing: 12) { // Increased spacing within this group
                        Text("API Credentials")
                            .font(.title3)
                        
                        // Conditional API Key Input
                        if settings.selectedProvider == "openai" {
                            apiKeyInputView(
                                label: "OpenAI API Key",
                                keyInput: $openAIKeyInput,
                                showKey: $showOpenAIKey,
                                saveAction: { newValue in
                                    settings.openAIKey = newValue
                                    settings.saveSettings()
                                }
                            )
                        } else if settings.selectedProvider == "groq" {
                            apiKeyInputView(
                                label: "Groq API Key",
                                keyInput: $groqKeyInput,
                                showKey: $showGroqKey,
                                saveAction: { newValue in
                                    settings.groqKey = newValue
                                    settings.saveSettings()
                                }
                            )
                        }
                        
                        // Test API Key Controls
                        apiKeyTestView()
                        
                    }
                    .padding(.vertical, 10) // Add vertical padding around the group
                    
                    Divider()
                    
                    // --- Model & Temperature Group ---
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Model & Temperature")
                            .font(.title3)
                        
                        // Model Picker
                        Picker("Model", selection: $settings.transcriptionModel) {
                            if settings.selectedProvider == "openai" {
                                Text("GPT-4o Mini").tag("gpt-4o-mini-transcribe")
                                Text("GPT-4o").tag("gpt-4o-transcribe")
                                Text("Whisper").tag("whisper-1")
                            } else {
                                Text("Whisper Large v3").tag("whisper-large-v3")
                                Text("Whisper Large v3 Turbo").tag("whisper-large-v3-turbo")
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden() // Hide label, title is sufficient
                        .onChange(of: settings.transcriptionModel) { oldValue, newValue in
                            settings.saveSettings()
                        }
                        
                        // Temperature Slider
                        VStack(alignment: .leading, spacing: 5) { // Reduced spacing for slider elements
                            Text("Temperature: \(settings.transcriptionTemperature, specifier: "%.2f")")
                                .font(.callout)
                            Slider(value: $settings.transcriptionTemperature, in: 0.0...1.0, step: 0.05) { _ in
                                settings.saveSettings()
                            }
                            Text("Lower temperature results in more deterministic output, higher temperature results in more varied output.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true) // Allow text wrapping
                        }
                        .padding(.top, 5) // Add space above slider
                        
                    }
                    .padding(.vertical, 10)
                    
                    Divider()
                    
                    // --- Microphone Group ---
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Audio Input")
                            .font(.title3)
                        
                        if availableMicrophones.isEmpty {
                            Text("No microphones found.")
                                .foregroundColor(.red)
                        } else {
                            Picker("Input Device", selection: $settings.selectedMicrophoneID) {
                                ForEach(availableMicrophones) { mic in
                                    Text(mic.name).tag(mic.id)
                                }
                            }
                            // Keep the label for Picker for accessibility, but it's visually integrated
                            .onChange(of: settings.selectedMicrophoneID) { oldValue, newValue in
                                settings.saveSettings()
                                if !newValue.isEmpty {
                                    startAudioMonitoring(deviceID: newValue)
                                } else {
                                    stopAudioMonitoring()
                                }
                            }
                            
                            // Audio level meter
                            microphoneLevelView()
                                .padding(.top, 5) // Space above meter
                        }
                    }
                    .padding(.top, 10) // Only top padding needed for the last group
                    
                }
                .padding() // Add padding around the entire content within ScrollView
            }
        }
        .frame(minWidth: 500, maxWidth: 600, minHeight: 550, maxHeight: 700) // Adjusted frame
        .onAppear {
            availableMicrophones = settings.getAvailableMicrophones()
            logger.log("Loaded \(availableMicrophones.count) microphones for Picker in SettingsView onAppear")

            if !settings.selectedMicrophoneID.isEmpty {
                startAudioMonitoring(deviceID: settings.selectedMicrophoneID)
            }
            
            openAIKeyInput = settings.openAIKey
            groqKeyInput = settings.groqKey
        }
        .onDisappear {
            stopAudioMonitoring()
            apiTestTask?.cancel()
        }
    }
    
    // MARK: - Subviews for Cleaner Body
    
    @ViewBuilder
    private func apiKeyInputView(label: String, keyInput: Binding<String>, showKey: Binding<Bool>, saveAction: @escaping (String) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 4) {
             // Text(label).font(.callout) // Label is now optional as it's clear from context
            HStack {
                if showKey.wrappedValue {
                    TextField(label, text: keyInput) // Use label as placeholder
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                } else {
                    SecureField(label, text: keyInput) // Use label as placeholder
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                }
                Button {
                    showKey.wrappedValue.toggle()
                } label: {
                    Image(systemName: showKey.wrappedValue ? "eye.slash.fill" : "eye.fill")
                        .foregroundColor(.secondary) // Use secondary color for icons
                }
                .buttonStyle(PlainButtonStyle())
                .contentShape(Rectangle()) // Ensure the button area is tappable
            }
            .onAppear { // Ensure local state matches manager on appear
                 if label.contains("OpenAI") { keyInput.wrappedValue = settings.openAIKey }
                 if label.contains("Groq") { keyInput.wrappedValue = settings.groqKey }
            }
            .onChange(of: keyInput.wrappedValue) { oldValue, newValue in
                saveAction(newValue) // Call the save action passed in
            }
        }
    }
    
    @ViewBuilder
    private func apiKeyTestView() -> some View {
        // Only show test button if a key exists for the selected provider
        if !currentAPIKey().isEmpty {
            HStack {
                Button("Test API Key") {
                    apiKeyTestResult = nil
                    testAPIKey()
                }
                .disabled(isTestingAPIKey)
                
                // Test Status Indicator
                if isTestingAPIKey {
                    ProgressView()
                        .scaleEffect(0.7) // Make spinner smaller
                        .frame(width: 20, height: 20) // Control layout space
                } else if let result = apiKeyTestResult {
                    switch result {
                    case .success:
                        Label("Valid Key", systemImage: "checkmark.circle.fill")
                            .foregroundColor(.green)
                    case .error(let msg):
                        Label("Invalid Key", systemImage: "xmark.circle.fill")
                            .help(msg)
                            .foregroundColor(Color.red)
                    case .networkError(let msg):
                        Label("Network Error", systemImage: "wifi.slash")
                            .help(msg)
                            .foregroundColor(Color.orange)
                    }
                }
                Spacer() // Push button and status to the left
            }
            .padding(.top, 5) // Space above the test button
        } else {
            Text("Enter an API key to enable testing.")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.top, 5)
        }
    }
    
    @ViewBuilder
    private func microphoneLevelView() -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Microphone Level")
                .font(.callout)
            HStack(spacing: 2) {
                ForEach(0..<20, id: \.self) { index in
                    Rectangle()
                        .fill(barColor(for: index))
                        .frame(width: 4, height: 16) // Explicit height
                }
            }
            .frame(height: 16) // Ensure HStack has the correct height
            .drawingGroup() // Optimize drawing for frequent updates
            
            if let error = audioMonitorError {
                Text("Monitor Error: \(error)")
                    .foregroundColor(.red)
                    .font(.caption)
            }
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
            // Adjusted color thresholds for better visual feedback
            if index < 10 { // Green up to 50%
                return .green
            } else if index < 16 { // Yellow up to 80%
                return .yellow
            } else { // Red above 80%
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
            
            let isValid = await aiManager.testAPIKey(apiKey: key)
            if Task.isCancelled { return }
            
            DispatchQueue.main.async {
                if isValid {
                    apiKeyTestResult = .success
                } else {
                    // If the key is invalid OR there was an internal (e.g., network) error handled by testAPIKey
                    apiKeyTestResult = .error("Invalid key or connection issue")
                }
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
                        // Smooth the audio level updates slightly
                         self.audioLevel = (self.audioLevel * 0.7) + (level * 0.3)
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
             logger.log("Failed to start audio monitoring: Invalid device ID format '\(deviceID)'", level: .error)
            audioMonitorError = "Invalid device ID format"
        }
    }
    
    private func stopAudioMonitoring() {
        audioMonitor?.stopMonitoring()
        audioMonitor = nil
         // Reset level visually when stopping
         DispatchQueue.main.async {
            self.audioLevel = 0
         }
    }
}
