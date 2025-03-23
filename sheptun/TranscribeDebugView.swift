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
                        Text("WebSocket:")
                            .gridColumnAlignment(.trailing)
                        Text(viewModel.connectionStatus)
                    }
                    
                    GridRow {
                        Text("Audio Status:")
                            .gridColumnAlignment(.trailing)
                        Text(viewModel.isRecordingAudio ? "Recording & Sending" : "Stopped")
                            .foregroundColor(viewModel.isRecordingAudio ? .green : .red)
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
                        Text("Audio Chunks Sent:")
                            .gridColumnAlignment(.trailing)
                        Text("\(viewModel.audioChunksSent)")
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
            
            // Control panel with separate buttons for connection and audio
            VStack(spacing: 10) {
                // First row - connection controls
                HStack(spacing: 20) {
                    Button(action: viewModel.toggleConnection) {
                        HStack {
                            Image(systemName: viewModel.isConnected ? "wifi.slash" : "wifi")
                            Text(viewModel.isConnected ? "Disconnect" : "Connect WebSocket")
                        }
                        .frame(minWidth: 150)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(viewModel.isConnected ? .orange : .blue)
                    
                    Picker("Model", selection: $viewModel.selectedModel) {
                        Text("GPT-4o").tag(OpenAIManager.TranscriptionModel.gpt4oTranscribe)
                        Text("GPT-4o Mini").tag(OpenAIManager.TranscriptionModel.gpt4oMiniTranscribe)
                    }
                    .pickerStyle(.menu)
                    .frame(width: 120)
                    .disabled(viewModel.isConnected || viewModel.isConnecting)
                    
                    Button(action: viewModel.clearTranscription) {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.bordered)
                }
                
                // Second row - audio controls
                HStack(spacing: 20) {
                    Button(action: viewModel.toggleAudioRecording) {
                        HStack {
                            Image(systemName: viewModel.isRecordingAudio ? "stop.circle.fill" : "mic.circle.fill")
                            Text(viewModel.isRecordingAudio ? "Stop Audio" : "Start Audio")
                        }
                        .frame(minWidth: 150)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(viewModel.isRecordingAudio ? .red : .green)
                    .disabled(!viewModel.isConnected)
                    .keyboardShortcut(.return, modifiers: [])
                    
                    // Audio debug button - useful for forcing audio buffer commit
                    Button(action: viewModel.forceAudioBufferCommit) {
                        Text("Force Commit")
                    }
                    .buttonStyle(.bordered)
                    .help("Force the current audio buffer to be committed")
                    .disabled(!viewModel.isRecordingAudio)
                    
                    // Combined button for easier use
                    Button(action: viewModel.toggleAllInOne) {
                        Text("All-in-One")
                    }
                    .buttonStyle(.bordered)
                    .help("Combined connect and start/stop audio in one button")
                }
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
    @Published var isRecordingAudio = false
    @Published var connectionStatus = "Disconnected"
    @Published var audioLevel: Float = 0.0
    @Published var sessionStartTime: Date?
    @Published var sessionDurationFormatted = "00:00"
    @Published var messagesReceived = 0
    @Published var audioChunksSent = 0
    @Published var lastError = ""
    @Published var selectedModel: OpenAIManager.TranscriptionModel = .gpt4oTranscribe
    
    // Timer for updating session duration and stats
    private var sessionTimer: Timer?
    private var statsUpdateTimer: Timer?
    
    init() {
        setupAudioLevelMonitoring()
        startStatsUpdateTimer()
    }
    
    func setupAudioLevelMonitoring() {
        // Observe audio level changes from the shared AudioRecorder
        Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.audioLevel = self.audioRecorder.audioLevel
        }
    }
    
    func startStatsUpdateTimer() {
        statsUpdateTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            
            // Update properties from OpenAIManager
            DispatchQueue.main.async {
                self.messagesReceived = self.openAIManager.messagesReceived
                self.audioChunksSent = self.openAIManager.audioChunksSent
                self.isRecordingAudio = self.openAIManager.isRecordingAudio
                
                // Update connection status
                self.isConnected = self.openAIManager.isConnected
                self.isConnecting = self.openAIManager.isConnecting
                
                if self.isConnected {
                    self.connectionStatus = "Connected"
                } else if self.isConnecting {
                    self.connectionStatus = "Connecting..."
                } else {
                    self.connectionStatus = "Disconnected"
                }
                
                // Check if there's an error from OpenAIManager
                if let error = self.openAIManager.lastError, !error.isEmpty, error != self.lastError {
                    self.lastError = error
                    self.logger.log("Error from OpenAIManager: \(error)", level: .error)
                }
            }
        }
    }
    
    // Combined function for backward compatibility
    func toggleTranscription() {
        toggleAllInOne()
    }
    
    // All-in-one function that both connects and starts audio
    func toggleAllInOne() {
        if isConnected {
            if isRecordingAudio {
                // If connected and recording, stop everything
                disconnectFromWebSocket()
            } else {
                // If connected but not recording, start audio
                startAudioRecording()
            }
        } else {
            // If not connected, connect to WebSocket
            connectToWebSocket()
        }
    }
    
    // Toggle just the WebSocket connection
    func toggleConnection() {
        if isConnected {
            disconnectFromWebSocket()
        } else {
            connectToWebSocket()
        }
    }
    
    // Toggle just the audio recording
    func toggleAudioRecording() {
        if isRecordingAudio {
            stopAudioRecording()
        } else {
            startAudioRecording()
        }
    }
    
    // Connect to WebSocket only
    func connectToWebSocket() {
        guard !isConnecting && !isConnected else { return }
        
        isConnecting = true
        connectionStatus = "Connecting..."
        lastError = ""
        
        logger.log("Connecting to WebSocket", level: .info)
        
        // Set timeout timer to prevent hanging
        let timeoutTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: false) { [weak self] _ in
            guard let self = self, self.isConnecting else { return }
            
            DispatchQueue.main.async {
                self.isConnecting = false
                self.connectionStatus = "Error: Connection timeout"
                self.lastError = "Connection timed out after 10 seconds"
                self.logger.log("WebSocket connection timed out", level: .error)
                self.openAIManager.stopTranscription()
            }
        }
        
        // Get OpenAI API key from settings
        let apiKey = settingsManager.openAIKey
        
        guard !apiKey.isEmpty else {
            isConnecting = false
            connectionStatus = "Error: No API Key"
            lastError = "API key not configured in settings"
            logger.log("Cannot connect - API key not configured", level: .error)
            return
        }
        
        // Start session timer
        sessionStartTime = Date()
        startSessionTimer()
        
        // Connect to WebSocket
        Task {
            do {
                logger.log("Starting WebSocket connection", level: .info)
                
                await openAIManager.connectToWebSocketOnly(
                    deviceID: "default",
                    model: selectedModel
                )
                
                // Setup transcription callback
                openAIManager.transcriptionCallback = { [weak self] text, isFinal in
                    guard let self = self else { return }
                    
                    DispatchQueue.main.async {
                        timeoutTimer.invalidate()  // Cancel timeout timer when we get a response
                        
                        if isFinal {
                            // For final transcriptions, append with a new line
                            if !self.transcriptionText.isEmpty {
                                self.transcriptionText.append("\n")
                            }
                            self.transcriptionText.append(text)
                            self.logger.log("Final transcription received: \(text)", level: .info)
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
                            self.transcriptionText.append(text)
                            self.logger.log("Partial transcription received: \(text)", level: .debug)
                        }
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    timeoutTimer.invalidate()
                    self.isConnecting = false
                    self.connectionStatus = "Error: \(error.localizedDescription)"
                    self.lastError = error.localizedDescription
                    self.logger.log("Error connecting to WebSocket: \(error)", level: .error)
                }
            }
        }
    }
    
    // Start audio recording and sending
    func startAudioRecording() {
        guard isConnected && !isRecordingAudio else {
            if !isConnected {
                lastError = "Cannot start audio: not connected"
                logger.log("Cannot start audio: not connected to WebSocket", level: .warning)
            }
            return
        }
        
        logger.log("Starting audio recording", level: .info)
        openAIManager.startAudioTransmission(deviceID: "default")
    }
    
    // Stop audio recording but keep connection
    func stopAudioRecording() {
        guard isRecordingAudio else { return }
        
        logger.log("Stopping audio recording", level: .info)
        openAIManager.stopAudioTransmission()
    }
    
    // Force audio buffer commit (for debugging)
    func forceAudioBufferCommit() {
        guard isConnected && isRecordingAudio else { return }
        
        logger.log("Forcing audio buffer commit", level: .info)
        openAIManager.commitAudioBuffer()
    }
    
    // Disconnect from WebSocket
    func disconnectFromWebSocket() {
        logger.log("Disconnecting from WebSocket", level: .info)
        openAIManager.stopTranscription()
        audioRecorder.stopRecording()
        stopSessionTimer()
        isConnected = false
        isConnecting = false
        isRecordingAudio = false
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
        stopAudioRecording()
        disconnectFromWebSocket()
        sessionTimer?.invalidate()
        statsUpdateTimer?.invalidate()
    }
} 