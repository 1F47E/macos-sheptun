import SwiftUI
import AVFoundation

struct SettingsView: View {
    @StateObject private var settings = SettingsManager.shared
    @State private var openAIKeyInput: String = ""
    @State private var groqKeyInput: String = ""
    @State private var availableMicrophones: [SettingsManager.MicrophoneDevice] = []
    @State private var isTestingAPIKey: Bool = false
    @State private var apiKeyTestResult: APIKeyTestResult?
    @State private var apiTestTask: Task<Void, Never>? = nil
    @State private var audioLevel: Float = 0
    @State private var audioMonitor: AudioLevelMonitor?
    @State private var audioMonitorError: String? = nil
    @Environment(\.dismiss) private var dismiss
    private let logger = Logger.shared
    
    enum APIKeyTestResult {
        case success
        case error(String)
        case networkError(String)
    }
    
    var body: some View {
        VStack(spacing: 20) {
          
            Form {
                Group {
                    Section(header: Text("Provider")) {
                        Picker("Provider", selection: $settings.selectedProvider) {
                            Text("OpenAI").tag("openai")
                            Text("Groq").tag("groq")
                        }
                        .pickerStyle(SegmentedPickerStyle())
                        .onChange(of: settings.selectedProvider) { _ in
                            settings.updateModelForProvider()
                            settings.saveSettings()
                        }
                    }
                    
                    if settings.selectedProvider == "openai" {
                        Section(header: Text("OpenAI API Key")) {
                            SecureField("OpenAI API Key", text: $openAIKeyInput)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                                .onAppear {
                                    openAIKeyInput = settings.openAIKey
                                }
                                .onChange(of: openAIKeyInput) { newValue in
                                    settings.openAIKey = newValue
                                    settings.saveSettings()
                                }
                        }
                        
                        Section(header: Text("")) {
                            Picker("Model", selection: $settings.transcriptionModel) {
                                Text("GPT-4o Mini").tag("gpt-4o-mini-transcribe")
                                Text("GPT-4o").tag("gpt-4o-transcribe")
                                Text("Whisper").tag("whisper-1")
                            }
                            .pickerStyle(SegmentedPickerStyle())
                            .onChange(of: settings.transcriptionModel) { _ in
                                settings.saveSettings()
                            }
                            
                            VStack(alignment: .leading) {
                                Text("Temperature: \(settings.transcriptionTemperature, specifier: "%.2f")")
                                Slider(value: $settings.transcriptionTemperature, in: 0.0...1.0, step: 0.05) { _ in
                                    settings.saveSettings()
                                }
                                Text("Lower values give more accurate results, higher values more creative")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.top, 10)
                        }
                    }
                    
                    if settings.selectedProvider == "groq" {
                        Section(header: Text("Groq API Key")) {
                            SecureField("Groq API Key", text: $groqKeyInput)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                                .onAppear {
                                    groqKeyInput = settings.groqKey
                                }
                                .onChange(of: groqKeyInput) { newValue in
                                    settings.groqKey = newValue
                                    settings.saveSettings()
                                }
                        }
                        
                        Section(header: Text("")) {
                            Picker("Model", selection: $settings.transcriptionModel) {
                                Text("Whisper Large v3").tag("whisper-large-v3")
                                Text("Whisper Large v3 Turbo").tag("whisper-large-v3-turbo")
                            }
                            .pickerStyle(SegmentedPickerStyle())
                            .onChange(of: settings.transcriptionModel) { _ in
                                settings.saveSettings()
                            }
                            
                            VStack(alignment: .leading) {
                                Text("Temperature: \(settings.transcriptionTemperature, specifier: "%.2f")")
                                Slider(value: $settings.transcriptionTemperature, in: 0.0...1.0, step: 0.05) { _ in
                                    settings.saveSettings()
                                }
                                Text("Lower values give more accurate results, higher values more creative")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.top, 10)
                        }
                    }
                    
                    // Test API Key Button
                    Button("Test API Key") {
                        self.testAPIKey()
                    }
                    .disabled(isTestingAPIKey || (settings.selectedProvider == "openai" && settings.openAIKey.isEmpty) || (settings.selectedProvider == "groq" && settings.groqKey.isEmpty))
                    
                    if isTestingAPIKey {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle())
                    } else if let result = apiKeyTestResult {
                        switch result {
                        case .success:
                            HStack {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                Text("API Key is valid")
                                    .foregroundColor(.green)
                            }
                        case .error(let message):
                            HStack {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.red)
                                Text("Invalid API Key: \(message)")
                                    .foregroundColor(.red)
                            }
                        case .networkError(let message):
                            HStack {
                                Image(systemName: "wifi.slash")
                                    .foregroundColor(.orange)
                                Text("Network error: \(message)")
                                    .foregroundColor(.orange)
                            }
                        }
                    }
                    
                    // Microphone section
                    Section(header: Text("Microphone")) {
                        if availableMicrophones.isEmpty {
                            Text("No microphones found")
                                .foregroundColor(.red)
                        } else {
                            Picker("Select Input Device", selection: $settings.selectedMicrophoneID) {
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
                            
                            // Audio level meter
                            VStack(alignment: .leading) {
                                Text("Microphone Level")
                                    .font(.headline)
                                    .padding(.top, 5)
                                
                                HStack(spacing: 2) {
                                    ForEach(0..<20, id: \.self) { index in
                                        Rectangle()
                                            .fill(barColor(for: index))
                                            .frame(height: 20)
                                    }
                                }
                                .frame(height: 20)
                                
                                if let error = audioMonitorError {
                                    Text("Error: \(error)")
                                        .foregroundColor(.red)
                                        .font(.caption)
                                }
                            }
                            .padding(.vertical, 10)
                        }
                    }
                }
                
                // ... hotkey section ...
            }
            .padding()
            
            Spacer()
        }
        .frame(minWidth: 500, minHeight: 500)
        .onAppear {
            loadMicrophones()
            if !settings.selectedMicrophoneID.isEmpty {
                startAudioMonitoring(deviceID: settings.selectedMicrophoneID)
            }
        }
        .onDisappear {
            stopAudioMonitoring()
            apiTestTask?.cancel()
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
    
    private func setupAudioMonitoring() {
        // Stop previous monitoring if any
        audioMonitor?.stopMonitoring()
        
        // Reset error state
        audioMonitorError = nil
        
        guard !settings.selectedMicrophoneID.isEmpty else { 
            logger.log("No microphone selected, cannot setup monitoring")
            audioMonitorError = "No microphone selected"
            return 
        }
        
        // Create a new monitor with the selected device ID
        if let deviceID = UInt32(settings.selectedMicrophoneID) {
            logger.log("Setting up audio monitoring for device ID: \(deviceID)")
            audioMonitor = AudioLevelMonitor(deviceID: deviceID)
            audioMonitor?.startMonitoring(
                levelUpdateHandler: { level in
                    DispatchQueue.main.async {
                        self.audioLevel = level
                    }
                },
                errorHandler: { error in
                    DispatchQueue.main.async {
                        self.audioMonitorError = error
                    }
                }
            )
        } else {
            logger.log("Invalid device ID format for audio monitoring", level: .error)
            audioMonitorError = "Invalid microphone ID format"
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
            
            if settings.selectedProvider == "openai" && settings.openAIKey.isEmpty {
                DispatchQueue.main.async {
                    apiKeyTestResult = .error("API Key is empty")
                }
                return
            }
            
            if settings.selectedProvider == "groq" && settings.groqKey.isEmpty {
                DispatchQueue.main.async {
                    apiKeyTestResult = .error("API Key is empty")
                }
                return
            }
            
            let apiKey = settings.getCurrentAPIKey()
            let provider = settings.getCurrentAIProvider()
            let aiManager = AIProviderFactory.getProvider(type: provider)
            
            do {
                let isValid = await aiManager.testAPIKey(apiKey: apiKey)
                
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
        
        // Stop audio monitoring
        audioMonitor?.stopMonitoring()
        audioMonitor = nil
    }
    
    private func loadMicrophones() {
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
    
    private func startAudioMonitoring(deviceID: String) {
        // Stop any existing audio monitoring
        stopAudioMonitoring()
        
        // Create a new audio monitor with the numeric device ID
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

// The AudioLevelMonitor class has been moved to its own file
// ... existing code ... 
// ... existing code ... 