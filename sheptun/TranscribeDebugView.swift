import SwiftUI

struct TranscribeDebugView: View {
    @StateObject private var viewModel = TranscribeViewModel()
    
    var body: some View {
        VStack(spacing: 16) {
            // Title and status section
            HStack {
                Text("Transcription Debug")
                    .font(.title)
                    .fontWeight(.bold)
                
                Spacer()
                
                // Connection status indicator
                HStack(spacing: 8) {
                    Circle()
                        .fill(viewModel.isConnected ? Color.green : (viewModel.isConnecting ? Color.yellow : Color.red))
                        .frame(width: 10, height: 10)
                    
                    Text(viewModel.connectionStatus)
                        .font(.caption)
                        .foregroundColor(viewModel.isConnected ? .green : (viewModel.isConnecting ? .yellow : .red))
                }
            }
            .padding([.horizontal, .top])
            
            Divider()
            
            // Stats section
            VStack(alignment: .leading, spacing: 12) {
                Text("Connection Stats")
                    .font(.headline)
                
                Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 8) {
                    GridRow {
                        Text("Status:")
                            .gridColumnAlignment(.trailing)
                        Text(viewModel.connectionStatus)
                    }
                    
                    GridRow {
                        Text("Model:")
                            .gridColumnAlignment(.trailing)
                        Text(viewModel.selectedModel.rawValue)
                    }
                    
                    GridRow {
                        Text("Audio Level:")
                            .gridColumnAlignment(.trailing)
                        HStack {
                            Text(String(format: "%.2f", viewModel.audioLevel))
                            ProgressView(value: viewModel.audioLevel)
                                .frame(width: 100)
                        }
                    }
                    
                    GridRow {
                        Text("Session Duration:")
                            .gridColumnAlignment(.trailing)
                        Text(viewModel.sessionDurationFormatted)
                    }
                    
                    GridRow {
                        Text("Messages Received:")
                            .gridColumnAlignment(.trailing)
                        Text("\(viewModel.messagesReceived)")
                    }
                    
                    GridRow {
                        Text("Last Error:")
                            .gridColumnAlignment(.trailing)
                        Text(viewModel.lastError.isEmpty ? "None" : viewModel.lastError)
                            .foregroundColor(.red)
                            .lineLimit(1)
                    }
                }
                .padding(.horizontal)
            }
            .padding(.horizontal)
            
            Divider()
            
            // Live animation
            ParticleWaveEffect(intensity: viewModel.audioLevel)
                .baseColor(.blue)
                .accentColor(.purple)
                .height(60)
                .padding(.horizontal)
            
            // Transcription text display
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Transcription")
                        .font(.headline)
                        .padding(.horizontal)
                    
                    if viewModel.transcriptionText.isEmpty && !viewModel.isConnected {
                        Text("Start transcription to see results...")
                            .italic()
                            .foregroundColor(.secondary)
                            .padding(.horizontal)
                    } else {
                        Text(viewModel.transcriptionText)
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(.windowBackgroundColor).opacity(0.3))
                            .cornerRadius(8)
                            .padding(.horizontal)
                    }
                }
            }
            .frame(maxHeight: .infinity)
            
            Divider()
            
            // Control panel
            HStack(spacing: 20) {
                Button(action: viewModel.toggleTranscription) {
                    HStack {
                        Image(systemName: viewModel.isConnected ? "stop.circle.fill" : "mic.circle.fill")
                        Text(viewModel.isConnected ? "Stop" : "Start Transcription")
                    }
                    .frame(minWidth: 150)
                }
                .keyboardShortcut(.return, modifiers: [])
                .buttonStyle(.borderedProminent)
                
                Picker("Model", selection: $viewModel.selectedModel) {
                    Text("GPT-4o").tag(OpenAIManager.TranscriptionModel.gpt4oTranscribe)
                    Text("GPT-4o Mini").tag(OpenAIManager.TranscriptionModel.gpt4oMiniTranscribe)
                    Text("Whisper-1").tag(OpenAIManager.TranscriptionModel.whisper1)
                }
                .pickerStyle(.menu)
                .frame(width: 120)
                
                Button(action: viewModel.clearTranscription) {
                    Image(systemName: "trash")
                }
                .buttonStyle(.bordered)
            }
            .padding()
        }
        .frame(minWidth: 500, minHeight: 400)
    }
}

// ViewModel to manage the transcription state and OpenAI connection
class TranscribeViewModel: ObservableObject {
    // OpenAI and audio objects
    private let openAIManager = OpenAIManager.shared
    private let audioRecorder = AudioRecorder.shared
    private let settingsManager = SettingsManager.shared
    private let logger = Logger.shared
    
    // Published properties for UI updates
    @Published var transcriptionText = ""
    @Published var isConnected = false
    @Published var isConnecting = false
    @Published var connectionStatus = "Disconnected"
    @Published var audioLevel: Float = 0.0
    @Published var sessionStartTime: Date?
    @Published var sessionDurationFormatted = "00:00"
    @Published var messagesReceived = 0
    @Published var lastError = ""
    @Published var selectedModel: OpenAIManager.TranscriptionModel = .gpt4oTranscribe
    
    // Timer for updating session duration
    private var sessionTimer: Timer?
    
    init() {
        setupAudioLevelMonitoring()
    }
    
    func setupAudioLevelMonitoring() {
        // Observe audio level changes from the shared AudioRecorder
        Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.audioLevel = self.audioRecorder.audioLevel
        }
    }
    
    func toggleTranscription() {
        if isConnected {
            stopTranscription()
        } else {
            startTranscription()
        }
    }
    
    func startTranscription() {
        guard !isConnecting else { return }
        
        isConnecting = true
        connectionStatus = "Connecting..."
        lastError = ""
        
        // Start recording audio
        audioRecorder.startRecording()
        
        // Start session timer
        sessionStartTime = Date()
        startSessionTimer()
        
        // Get OpenAI API key from settings
        let apiKey = settingsManager.openAIKey
        
        guard !apiKey.isEmpty else {
            isConnecting = false
            connectionStatus = "Error: No API Key"
            lastError = "API key not configured in settings"
            logger.log("Cannot start transcription - API key not configured", level: .error)
            return
        }
        
        // Start transcription with ephemeral token for better WebSocket auth
        Task {
            await openAIManager.startLiveTranscriptionWithEphemeralToken(
                apiKey: apiKey,
                model: selectedModel,
                updateHandler: { [weak self] result in
                    guard let self = self else { return }
                    
                    DispatchQueue.main.async {
                        switch result {
                        case .success(let transcription):
                            self.messagesReceived += 1
                            
                            if transcription.isFinal {
                                // For final transcriptions, append with a new line
                                if !self.transcriptionText.isEmpty {
                                    self.transcriptionText.append("\n")
                                }
                                self.transcriptionText.append(transcription.text)
                            } else {
                                // For partial transcriptions, replace the last line
                                let lines = self.transcriptionText.components(separatedBy: "\n")
                                if lines.count > 0 {
                                    var newLines = lines
                                    if newLines.count > 1 {
                                        // Keep all but the last line
                                        newLines = Array(lines.dropLast())
                                        self.transcriptionText = newLines.joined(separator: "\n")
                                        self.transcriptionText.append("\n")
                                    } else {
                                        // If there's only one line, clear it
                                        self.transcriptionText = ""
                                    }
                                }
                                self.transcriptionText.append(transcription.text)
                            }
                            
                            // Update connection status
                            if !self.isConnected {
                                self.isConnected = true
                                self.isConnecting = false
                                self.connectionStatus = "Connected"
                            }
                            
                        case .failure(let error):
                            self.lastError = error.localizedDescription
                            self.logger.log("Transcription error: \(error)", level: .error)
                            
                            if self.isConnecting {
                                self.connectionStatus = "Connection failed"
                                self.isConnecting = false
                            } else if self.isConnected {
                                // If we were connected, update status
                                self.connectionStatus = "Disconnected (Error)"
                                self.isConnected = false
                                self.stopSessionTimer()
                            }
                        }
                    }
                }
            )
        }
    }
    
    func stopTranscription() {
        openAIManager.stopLiveTranscription()
        audioRecorder.stopRecording()
        stopSessionTimer()
        isConnected = false
        isConnecting = false
        connectionStatus = "Disconnected"
    }
    
    func clearTranscription() {
        transcriptionText = ""
    }
    
    private func startSessionTimer() {
        sessionTimer?.invalidate()
        sessionTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self, let startTime = self.sessionStartTime else { return }
            
            let duration = Date().timeIntervalSince(startTime)
            let minutes = Int(duration) / 60
            let seconds = Int(duration) % 60
            self.sessionDurationFormatted = String(format: "%02d:%02d", minutes, seconds)
        }
    }
    
    private func stopSessionTimer() {
        sessionTimer?.invalidate()
        sessionTimer = nil
        sessionStartTime = nil
    }
    
    deinit {
        stopTranscription()
        sessionTimer?.invalidate()
    }
} 