import SwiftUI

struct TranscribeDebugView: View {
    @StateObject private var viewModel = TranscribeViewModel()
    
    var body: some View {
        VStack(spacing: 0) {
            headerView
            
            Divider()
            
            ZStack {
                transcriptionView
                
                if viewModel.isTranscribing || viewModel.isInitializingRecording {
                    loadingView
                }
            }
            
            controlsView
        }
        .frame(minWidth: 550, minHeight: 450)
        .background(Color(.windowBackgroundColor))
        .onAppear {
            viewModel.setupForView()
        }
        .onDisappear {
            viewModel.cleanup()
        }
    }
    
    // Header with title and status
    private var headerView: some View {
        HStack {
            Text("Voice Transcription")
                .font(.system(size: 22, weight: .semibold))
            
            Spacer()
            
            statusBadge
        }
        .padding()
    }
    
    // Status badge that changes color based on state
    private var statusBadge: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
            
            Text(viewModel.statusText)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(statusColor)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(statusColor.opacity(0.1))
        .cornerRadius(16)
    }
    
    // Color for status changes based on recording/transcribing state
    private var statusColor: Color {
        if viewModel.isRecordingAudio {
            return .red
        } else if viewModel.isTranscribing || viewModel.isInitializingRecording {
            return .orange
        } else if !viewModel.lastError.isEmpty {
            return .red
        } else {
            return .green
        }
    }
    
    // Audio visualization and model selection
    private var audioVisualizationView: some View {
        VStack(spacing: 10) {
            HStack {
                Text("Audio Level:")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Text(String(format: "%.2f", viewModel.audioLevel))
                    .monospacedDigit()
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
            }
            
            ParticleWaveEffect(intensity: viewModel.audioLevel)
                .baseColor(.blue)
                .accentColor(.indigo)
                .height(60)
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                )
            
            HStack {
                Text("Model:")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Picker("", selection: $viewModel.selectedModel) {
                    Text("Whisper").tag(OpenAIManager.TranscriptionModel.whisper1)
                    Text("GPT-4o").tag(OpenAIManager.TranscriptionModel.gpt4oTranscribe)
                    Text("GPT-4o Mini").tag(OpenAIManager.TranscriptionModel.gpt4oMiniTranscribe)
                }
                .pickerStyle(.menu)
                .frame(width: 130)
                .disabled(viewModel.isRecordingAudio || viewModel.isTranscribing || viewModel.isInitializingRecording)
            }
            
            if !viewModel.lastError.isEmpty {
                errorView
            }
        }
        .padding()
        .background(Color(.windowBackgroundColor).opacity(0.6))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.secondary.opacity(0.1), lineWidth: 1)
        )
        .padding(.horizontal)
        .padding(.top)
    }
    
    // Main transcription content area
    private var transcriptionView: some View {
        VStack(spacing: 0) {
            audioVisualizationView
            
            Spacer()
                .frame(height: 16)
            
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Text("Transcription")
                            .font(.headline)
                        
                        Spacer()
                        
                        if !viewModel.transcriptionText.isEmpty {
                            Button(action: viewModel.clearTranscription) {
                                Label("Clear", systemImage: "trash")
                                    .font(.system(size: 12))
                            }
                            .buttonStyle(.plain)
                            .foregroundColor(.secondary)
                        }
                    }
                    
                    if viewModel.transcriptionText.isEmpty && !viewModel.isRecordingAudio && !viewModel.isTranscribing && !viewModel.isInitializingRecording {
                        emptyTranscriptionView
                    } else {
                        Text(viewModel.transcriptionText)
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(.textBackgroundColor).opacity(0.4))
                            .cornerRadius(10)
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                            )
                    }
                }
                .padding()
            }
        }
    }
    
    // Empty state view
    private var emptyTranscriptionView: some View {
        VStack(spacing: 16) {
            Image(systemName: "waveform")
                .font(.system(size: 36))
                .foregroundColor(.secondary.opacity(0.5))
            
            Text("Start recording to see transcription")
                .font(.system(size: 15))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 150)
        .padding()
        .background(Color(.textBackgroundColor).opacity(0.2))
        .cornerRadius(10)
    }
    
    // Error display
    private var errorView: some View {
        HStack(alignment: .top) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.red)
            
            Text(viewModel.lastError)
                .font(.system(size: 13))
                .foregroundColor(.red)
            
            Spacer()
        }
        .padding(12)
        .background(Color.red.opacity(0.1))
        .cornerRadius(8)
    }
    
    // Loading spinner overlay
    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.2)
                .progressViewStyle(CircularProgressViewStyle(tint: .blue))
            
            Text(viewModel.isInitializingRecording ? "Initializing audio..." : "Transcribing...")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.secondary)
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.windowBackgroundColor).opacity(0.9))
                .shadow(color: Color.black.opacity(0.1), radius: 10)
        )
    }
    
    // Bottom controls
    private var controlsView: some View {
        VStack(spacing: 16) {
            Divider()
            
            HStack(spacing: 20) {
                recordButton
                
                Spacer()
                
                HStack(spacing: 8) {
                    Image(systemName: "clock")
                        .foregroundColor(.secondary)
                    
                    Text(viewModel.sessionDurationFormatted)
                        .font(.system(size: 15, weight: .medium, design: .monospaced))
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 12)
        }
    }
    
    // Record/stop button
    private var recordButton: some View {
        Button(action: viewModel.toggleRecording) {
            HStack(spacing: 12) {
                Image(systemName: viewModel.isRecordingAudio ? "stop.circle.fill" : "mic.circle.fill")
                    .font(.system(size: 20))
                
                Text(viewModel.isRecordingAudio ? "Stop Recording" : "Start Recording")
                    .font(.system(size: 15, weight: .medium))
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 16)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(viewModel.isRecordingAudio ? Color.red : Color.blue)
            )
            .foregroundColor(.white)
        }
        .buttonStyle(.plain)
        .disabled(viewModel.isTranscribing || viewModel.isInitializingRecording)
        .keyboardShortcut(.return, modifiers: [])
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
    @Published var isRecordingAudio = false
    @Published var statusText = "Ready"
    @Published var audioLevel: Float = 0.0
    @Published var sessionStartTime: Date?
    @Published var sessionDurationFormatted = "00:00"
    @Published var lastError = ""
    @Published var selectedModel: OpenAIManager.TranscriptionModel = .whisper1
    @Published var isTranscribing = false
    @Published var isInitializingRecording = false
    
    // Task management
    private var recordingTask: Task<Void, Never>?
    private var transcriptionTask: Task<Void, Never>?
    
    // Timer for updating session duration and stats
    private var sessionTimer: Timer?
    private var statsUpdateTimer: Timer?
    
    func setupForView() {
        setupAudioLevelMonitoring()
        startStatsUpdateTimer()
        
        // Reset all states
        isInitializingRecording = false
        isTranscribing = false
        isRecordingAudio = openAIManager.isRecordingAudio
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
                self.isRecordingAudio = self.openAIManager.isRecordingAudio
                
                // Update status text
                if self.isInitializingRecording {
                    self.statusText = "Initializing..."
                } else if self.isRecordingAudio {
                    self.statusText = "Recording"
                } else if self.isTranscribing {
                    self.statusText = "Transcribing..."
                } else if !self.lastError.isEmpty {
                    self.statusText = "Error"
                } else if !self.transcriptionText.isEmpty {
                    self.statusText = "Completed"
                } else {
                    self.statusText = "Ready"
                }
                
                // Check if there's an error from OpenAIManager
                if let error = self.openAIManager.lastError, !error.isEmpty, error != self.lastError {
                    self.lastError = error
                    self.logger.log("Error from OpenAIManager: \(error)", level: .error)
                }
            }
        }
    }
    
    // Toggle recording state
    func toggleRecording() {
        if isRecordingAudio {
            stopRecordingAndTranscribe()
        } else {
            startRecording()
        }
    }
    
    // Start recording
    func startRecording() {
        guard !isRecordingAudio && !isInitializingRecording && !isTranscribing else { return }
        
        // Get OpenAI API key from settings
        let apiKey = settingsManager.openAIKey
        
        guard !apiKey.isEmpty else {
            statusText = "Error: No API Key"
            lastError = "API key not configured in settings"
            logger.log("Cannot start recording - API key not configured", level: .error)
            return
        }
        
        // Clear previous error
        lastError = ""
        
        // Set initializing state
        DispatchQueue.main.async {
            self.isInitializingRecording = true
            self.statusText = "Initializing..."
        }
        
        // Cancel any existing task
        recordingTask?.cancel()
        
        // Start recording in a background task
        recordingTask = Task { [weak self] in
            guard let self = self else { return }
            
            do {
                // Start session timer
                DispatchQueue.main.async {
                    self.sessionStartTime = Date()
                    self.startSessionTimer()
                }
                
                self.logger.log("Starting audio recording", level: .info)
                
                // Get the microphone device ID
                let deviceID = self.settingsManager.selectedMicrophoneID.isEmpty ? 
                             "default" : self.settingsManager.selectedMicrophoneID
                
                // Start recording through OpenAIManager
                self.openAIManager.startRecording(deviceID: deviceID)
                
                // Wait a small amount of time to check if recording actually started
                try await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
                
                // Update state on main thread when recording has started
                await MainActor.run {
                    self.isInitializingRecording = false
                    
                    if self.openAIManager.isRecordingAudio {
                        self.logger.log("Recording started successfully", level: .info)
                    } else {
                        self.lastError = self.openAIManager.lastError ?? "Failed to start recording"
                        self.logger.log("Failed to start recording: \(self.lastError)", level: .error)
                    }
                }
            } catch {
                await MainActor.run {
                    self.isInitializingRecording = false
                    self.lastError = "Audio initialization error: \(error.localizedDescription)"
                    self.logger.log("Audio initialization error: \(error)", level: .error)
                }
            }
        }
    }
    
    // Stop recording and transcribe
    func stopRecordingAndTranscribe() {
        guard isRecordingAudio else { return }
        
        logger.log("Stopping recording and starting transcription", level: .info)
        
        // Update UI immediately
        DispatchQueue.main.async {
            self.isTranscribing = true
            self.statusText = "Transcribing..."
        }
        
        let apiKey = settingsManager.openAIKey
        let model = selectedModel
        
        // Cancel any existing tasks
        transcriptionTask?.cancel()
        
        // Stop recording and transcribe in a background task
        transcriptionTask = Task { [weak self] in
            guard let self = self else { return }
            
            // Stop recording and transcribe
            self.openAIManager.stopRecordingAndTranscribe(
                apiKey: apiKey,
                model: model,
                prompt: "",
                language: ""
            ) { [weak self] result in
                guard let self = self else { return }
                
                DispatchQueue.main.async {
                    self.isTranscribing = false
                    
                    switch result {
                    case .success(let text):
                        if !self.transcriptionText.isEmpty {
                            self.transcriptionText.append("\n")
                        }
                        self.transcriptionText.append(text)
                        self.logger.log("Transcription completed: \(text)", level: .info)
                        self.statusText = "Completed"
                        
                    case .failure(let error):
                        self.lastError = error.localizedDescription
                        self.logger.log("Transcription error: \(error)", level: .error)
                        self.statusText = "Error"
                    }
                    
                    self.stopSessionTimer()
                }
            }
        }
    }
    
    func clearTranscription() {
        transcriptionText = ""
        lastError = ""
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
        sessionDurationFormatted = "00:00"
    }
    
    func cleanup() {
        // Cancel all tasks
        recordingTask?.cancel()
        transcriptionTask?.cancel()
        
        // Stop timers
        sessionTimer?.invalidate()
        statsUpdateTimer?.invalidate()
        
        // Stop all operations
        openAIManager.stopTranscription()
    }
    
    deinit {
        cleanup()
    }
} 