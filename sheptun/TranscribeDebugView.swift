import SwiftUI
import AVFoundation

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
                    Text("GPT-4o").tag(OpenAIManager.TranscriptionModel.gpt4oTranscribe)
                    Text("GPT-4o Mini").tag(OpenAIManager.TranscriptionModel.gpt4oMiniTranscribe)
                    Text("Whisper").tag(OpenAIManager.TranscriptionModel.whisper1)
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
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.red)
                .font(.system(size: 16))
            
            VStack(alignment: .leading, spacing: 6) {
                Text(viewModel.lastError)
                    .font(.system(size: 13))
                    .foregroundColor(.red)
                    .fixedSize(horizontal: false, vertical: true)
                
                if viewModel.lastError.contains("microphone access") || 
                   viewModel.lastError.contains("permission denied") {
                    Button(action: openSystemPreferences) {
                        Text("Open System Settings")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .buttonStyle(.borderless)
                    .padding(.top, 2)
                }
            }
            
            Spacer()
        }
        .padding(12)
        .background(Color.red.opacity(0.1))
        .cornerRadius(8)
    }
    
    private func openSystemPreferences() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") else { return }
        NSWorkspace.shared.open(url)
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
            
            HStack {
                // Audio stats
                if viewModel.recordedAudioSize > 0 {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Audio: \(viewModel.recordedAudioSizeFormatted) KB")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(.secondary)
                        
                        Text("Duration: \(viewModel.recordedAudioDurationFormatted)")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(.secondary)
                        
                        if viewModel.apiResponseTime > 0 {
                            Text("API Response: \(String(format: "%.2f", viewModel.apiResponseTime))s")
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.horizontal)
                }
                
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
            
            // Control buttons
            HStack(spacing: 16) {
                recordButton
                
                Spacer()
                
                if viewModel.recordedAudioAvailable {
                    transcribeButton
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
    
    // Transcribe button
    private var transcribeButton: some View {
        Button(action: viewModel.transcribeRecordedAudio) {
            HStack(spacing: 12) {
                Image(systemName: "waveform.circle.fill")
                    .font(.system(size: 20))
                
                Text("Transcribe")
                    .font(.system(size: 15, weight: .medium))
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 16)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.green)
            )
            .foregroundColor(.white)
        }
        .buttonStyle(.plain)
        .disabled(viewModel.isTranscribing || viewModel.isInitializingRecording || viewModel.isRecordingAudio || !viewModel.recordedAudioAvailable)
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
    @Published var selectedModel: OpenAIManager.TranscriptionModel = .gpt4oTranscribe
    @Published var isTranscribing = false
    @Published var isInitializingRecording = false
    @Published var recordedAudioSize: Int = 0
    @Published var recordedAudioSizeFormatted: String = "0.0"
    @Published var recordedAudioDurationFormatted: String = "00:00"
    @Published var apiResponseTime: Double = 0.0
    @Published var recordedAudioAvailable: Bool = false
    
    // Task management
    private var recordingTask: Task<Void, Never>?
    private var transcriptionTask: Task<Void, Never>?
    
    // Timer for updating session duration and stats
    private var sessionTimer: Timer?
    private var statsUpdateTimer: Timer?
    
    // Persistent properties to store recorded audio data
    private var recordedAudioData: Data? = nil
    private var recordedAudioFormat: AVAudioFormat? = nil
    private var recordedAudioDuration: TimeInterval = 0
    
    func setupForView() {
        setupAudioLevelMonitoring()
        startStatsUpdateTimer()
        
        // Reset all states
        isInitializingRecording = false
        isTranscribing = false
        isRecordingAudio = openAIManager.isRecordingAudio
        
        // Check if we have stored audio data
        updateRecordedAudioInfo()
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
    
    private func updateRecordedAudioInfo() {
        if let audioData = recordedAudioData {
            recordedAudioSize = audioData.count
            recordedAudioSizeFormatted = String(format: "%.1f", Double(audioData.count) / 1024.0)
            recordedAudioAvailable = true
        } else {
            recordedAudioSize = 0
            recordedAudioSizeFormatted = "0.0"
            recordedAudioAvailable = false
        }
    }
    
    // Toggle recording state
    func toggleRecording() {
        if isRecordingAudio {
            stopRecording()
        } else {
            startRecording()
        }
    }
    
    // Start recording
    func startRecording() {
        guard !isRecordingAudio && !isInitializingRecording && !isTranscribing else { return }
        
        // Clear errors from any previous session
        lastError = ""
        
        // Check if we need to clean up temporary files
        cleanupTemporaryFiles()
        
        // Set initializing state
        DispatchQueue.main.async {
            self.isInitializingRecording = true
            self.statusText = "Initializing..."
        }
        
        // Cancel any existing task
        recordingTask?.cancel()
        
        // Create a task to handle initialization
        recordingTask = Task { [weak self] in
            guard let self = self else { return }
            
            do {
                // Check for microphone permission
                let permissionStatus = await checkMicrophonePermission()
                if permissionStatus != .granted {
                    await MainActor.run {
                        self.isInitializingRecording = false
                        self.lastError = "Microphone access denied. Please allow microphone access in System Settings."
                        self.logger.log("Recording failed: Microphone permission denied", level: .error)
                        self.stopSessionTimer() // Stop timer if permission denied
                    }
                    return
                }
                
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
                        self.stopSessionTimer() // Stop timer if recording failed to start
                    }
                }
            } catch {
                await MainActor.run {
                    self.isInitializingRecording = false
                    self.lastError = "Audio initialization error: \(error.localizedDescription)"
                    self.logger.log("Audio initialization error: \(error)", level: .error)
                    self.stopSessionTimer() // Stop timer if error occurred
                }
            }
        }
    }
    
    // Check microphone permission
    enum PermissionStatus {
        case granted
        case denied
        case undetermined
    }
    
    private func checkMicrophonePermission() async -> PermissionStatus {
        return await withCheckedContinuation { continuation in
            switch AVCaptureDevice.authorizationStatus(for: .audio) {
            case .authorized:
                logger.log("Microphone permission already granted", level: .debug)
                continuation.resume(returning: .granted)
                
            case .denied, .restricted:
                logger.log("Microphone permission denied", level: .error)
                continuation.resume(returning: .denied)
                
            case .notDetermined:
                logger.log("Requesting microphone permission", level: .info)
                AVCaptureDevice.requestAccess(for: .audio) { granted in
                    self.logger.log("Microphone permission request result: \(granted ? "granted" : "denied")", level: .info)
                    continuation.resume(returning: granted ? .granted : .denied)
                }
                
            @unknown default:
                logger.log("Unknown microphone permission status", level: .warning)
                continuation.resume(returning: .undetermined)
            }
        }
    }
    
    // Stop recording without transcribing
    func stopRecording() {
        // Guard against multiple calls to stopRecording()
        guard isRecordingAudio else {
            logger.log("stopRecording() called while not recording, ignoring", level: .debug)
            return
        }
        
        // Mark as not recording immediately to prevent multiple calls
        isRecordingAudio = false
        
        logger.log("Stopping audio recording...", level: .info)
        
        // Calculate actual recording duration before stopping
        let actualDuration = Date().timeIntervalSince(sessionStartTime ?? Date())
        let formattedDuration = String(format: "%.2f", actualDuration)
        
        // Store the audio format before stopping
        recordedAudioFormat = audioRecorder.audioFormat
        
        // Capture audio buffer before stopping the recording
        if let audioData = audioRecorder.getLatestAudioBuffer() {
            recordedAudioData = audioData
            recordedAudioSize = audioData.count
            recordedAudioDuration = actualDuration
            recordedAudioDurationFormatted = formattedDuration
            recordedAudioAvailable = true
            logger.log("Recorded audio saved: \(recordedAudioSize) bytes, \(recordedAudioDuration) seconds", level: .info)
        } else {
            logger.log("No audio data available after recording", level: .warning)
            recordedAudioAvailable = false
        }
        
        // Stop the recording - use the OpenAIManager if it was started through it
        if openAIManager.isRecordingAudio {
            openAIManager.stopRecording()
        } else {
            // Direct stop if needed
            audioRecorder.stopRecording()
        }
        
        // Update UI state
        DispatchQueue.main.async {
            self.updateRecordedAudioInfo()
        }
        
        // Stop the session timer
        stopSessionTimer()
    }
    
    // Transcribe the previously recorded audio
    func transcribeRecordedAudio() {
        guard !isRecordingAudio && !isTranscribing && !isInitializingRecording else { return }
        guard let audioData = recordedAudioData, !audioData.isEmpty else {
            lastError = "No recorded audio available"
            return
        }
        
        // Get OpenAI API key from settings
        let apiKey = settingsManager.openAIKey
        
        guard !apiKey.isEmpty else {
            statusText = "Error: No API Key"
            lastError = "API key not configured in settings"
            logger.log("Cannot transcribe - API key not configured", level: .error)
            return
        }
        
        // Clear previous error
        lastError = ""
        
        // Update UI immediately
        DispatchQueue.main.async {
            self.isTranscribing = true
            self.statusText = "Transcribing..."
        }
        
        let model = selectedModel
        
        // Cancel any existing tasks
        transcriptionTask?.cancel()
        
        // Start time tracking for API response time
        let startTime = Date()
        
        // Create a temporary file for the audio data
        transcriptionTask = Task { [weak self] in
            guard let self = self else { return }
            
            do {
                let tempDir = NSTemporaryDirectory()
                let tempFilename = "recording_\(Int(Date().timeIntervalSince1970)).wav"
                let tempURL = URL(fileURLWithPath: tempDir).appendingPathComponent(tempFilename)
                
                logger.log("Creating temporary audio file at: \(tempURL.path)", level: .debug)
                
                // Create a WAV file from the PCM data if we have format information
                if let audioFormat = self.recordedAudioFormat {
                    self.logger.log("Creating WAV file for transcription with format: \(audioFormat.description)", level: .debug)
                    
                    if let wavData = self.openAIManager.createWavData(fromPCMData: audioData, format: audioFormat) {
                        try wavData.write(to: tempURL)
                        self.logger.log("Created WAV file with size: \(wavData.count) bytes at \(tempURL.path)", level: .debug)
                    } else {
                        self.logger.log("Failed to create WAV file, attempting direct write to \(tempURL.path)", level: .warning)
                        try audioData.write(to: tempURL)
                    }
                } else {
                    self.logger.log("No audio format available, writing raw data to \(tempURL.path)", level: .warning)
                    try audioData.write(to: tempURL)
                }
                
                // Update UI to show model being used
                await MainActor.run {
                    self.statusText = "Transcribing with \(model.rawValue)..."
                }
                
                // Start transcription
                self.logger.log("Starting transcription with model: \(model.rawValue)", level: .info)
                let result = await self.openAIManager.transcribeAudioFile(
                    audioFileURL: tempURL,
                    apiKey: apiKey,
                    model: model,
                    prompt: "",
                    language: ""
                )
                
                // Calculate API response time
                let responseTime = Date().timeIntervalSince(startTime)
                
                DispatchQueue.main.async {
                    self.isTranscribing = false
                    self.apiResponseTime = responseTime
                    
                    self.logger.log("API response time: \(responseTime) seconds", level: .info)
                    
                    switch result {
                    case .success(let text):
                        if !self.transcriptionText.isEmpty {
                            self.transcriptionText.append("\n\n")
                        }
                        self.transcriptionText.append(text)
                        self.logger.log("Transcription completed: \(text)", level: .info)
                        self.statusText = "Completed"
                        
                    case .failure(let error):
                        self.lastError = error.localizedDescription
                        self.logger.log("Transcription error: \(error)", level: .error)
                        self.statusText = "Error"
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    self.isTranscribing = false
                    self.lastError = "Failed to process audio: \(error.localizedDescription)"
                    self.logger.log("Audio processing error: \(error)", level: .error)
                }
            }
        }
    }
    
    func stopRecordingAndTranscribe() {
        // Guard against multiple calls to stopRecordingAndTranscribe()
        guard isRecordingAudio else {
            logger.log("stopRecordingAndTranscribe() called while not recording, ignoring", level: .debug)
            return
        }
        
        // Mark as not recording immediately to prevent multiple calls
        isRecordingAudio = false
        
        logger.log("Stopping recording and starting transcription", level: .info)
        
        // Update UI state
        isTranscribing = true
        statusText = "Transcribing..."
        
        // Record start time for API timing
        let transcriptionStartTime = Date()
        
        // Calculate actual recording duration before stopping
        let actualDuration = sessionStartTime != nil ? Date().timeIntervalSince(sessionStartTime!) : 0
        
        // Format the duration string
        let minutes = Int(actualDuration) / 60
        let seconds = Int(actualDuration) % 60
        recordedAudioDurationFormatted = String(format: "%02d:%02d", minutes, seconds)
        
        // Stop any existing transcription task
        transcriptionTask?.cancel()
        
        // Capture audio buffer before stopping the recording
        guard let audioData = AudioRecorder.shared.getLatestAudioBuffer() else {
            logger.log("No audio data available for transcription", level: .warning)
            isTranscribing = false
            statusText = "Failed - No audio data"
            return
        }
        
        // Save recorded audio information
        recordedAudioData = audioData
        recordedAudioSize = audioData.count
        recordedAudioDuration = actualDuration
        
        // Stop the recording
        AudioRecorder.shared.stopRecording()
        
        // Stop the session timer
        stopSessionTimer()
        
        // Rest of the transcription code remains as is
        // ...
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
    
    private func cleanupTemporaryFiles() {
        // Get the temporary directory
        let tempDir = NSTemporaryDirectory()
        let tempDirURL = URL(fileURLWithPath: tempDir)
        
        do {
            // Get all files in the temporary directory
            let fileURLs = try FileManager.default.contentsOfDirectory(at: tempDirURL, includingPropertiesForKeys: nil)
            
            // Find and delete only our recording WAV files, preserving the M4A file
            for fileURL in fileURLs {
                // Only clean up WAV files that we create, not the M4A file
                if fileURL.lastPathComponent.starts(with: "recording_") && fileURL.pathExtension.lowercased() == "wav" {
                    try FileManager.default.removeItem(at: fileURL)
                    logger.log("Cleaned up previous recording file: \(fileURL.path)", level: .debug)
                }
            }
            
            logger.log("Temporary directory cleanup completed. M4A file preserved for reuse.", level: .debug)
        } catch {
            logger.log("Error cleaning up temporary files: \(error.localizedDescription)", level: .warning)
        }
    }
} 