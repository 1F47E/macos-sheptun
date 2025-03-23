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
                    Text("GPT-4o-transcribe").tag("gpt-4o-transcribe")
                    Text("GPT-4o-mini-transcribe").tag("gpt-4o-mini-transcribe")
                    Text("Whisper").tag("whisper-1")
                    Text("Whisper Large v3").tag("whisper-large-v3")
                    Text("Whisper Large v3 Turbo").tag("whisper-large-v3-turbo")
                }
                .pickerStyle(.menu)
                .frame(width: 180)
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
    // MARK: - Properties
    
    @ObservedObject private var audioRecorder = AudioRecorder.shared
    private let settingsManager = SettingsManager.shared
    private let logger = Logger.shared
    
    // Recording state
    @Published var isRecordingAudio = false
    @Published var isInitializingRecording = false
    @Published var sessionTimer: Timer?
    @Published var sessionDuration: TimeInterval = 0
    @Published var sessionStartTime: Date?
    
    // Transcription state
    @Published var isTranscribing = false
    @Published var transcriptionText = ""
    @Published var statusText = "Ready"
    @Published var lastError = ""
    
    // Recording info
    @Published var recordedAudioDuration: TimeInterval = 0
    @Published var recordedAudioDurationFormatted = "00:00"
    @Published var recordedAudioSize: Int = 0
    @Published var microphone = "Default"
    
    // API info
    @Published var selectedModel: String = "gpt-4o-mini-transcribe"
    @Published var apiResponseTime: Double = 0.0
    @Published var recordedAudioAvailable: Bool = false
    @Published var recordedAudioPath: String?
    
    // Task management
    private var recordingTask: Task<Void, Never>?
    private var transcriptionTask: Task<Void, Never>?
    
    // For stats display
    private var statsUpdateTimer: Timer?
    @Published var errorMessage: String = ""
    @Published var transcribedText: String = ""
    @Published var rawAudioSize: Int = 0
    @Published var processedDataSize: Int = 0
    @Published var transcriptionDuration: TimeInterval = 0
    
    // UI info display
    @Published var showRecordingInfo = true
    @Published var showSettings = false
    
    // Published properties for UI updates
    @Published var audioLevel: Float = 0.0
    @Published var sessionDurationFormatted = "00:00"
    @Published var recordedAudioSizeFormatted: String = "0.0"
    
    // Initialize selected model from settings
    init() {
        selectedModel = settingsManager.transcriptionModel
    }
    
    func setupForView() {
        setupAudioLevelMonitoring()
        startStatsUpdateTimer()
        
        // Reset all states
        isInitializingRecording = false
        isTranscribing = false
        isRecordingAudio = settingsManager.isRecordingAudio
        
        // Check if we have stored audio file
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
                self.isRecordingAudio = self.settingsManager.isRecordingAudio
                
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
                if let error = self.settingsManager.lastError, !error.isEmpty, error != self.lastError {
                    self.lastError = error
                    self.logger.log("Error from OpenAIManager: \(error)", level: .error)
                }
            }
        }
    }
    
    private func updateRecordedAudioInfo() {
        // Check if there's a recording file available
        if let recordedFileURL = audioRecorder.getRecordingFileURL() {
            recordedAudioPath = recordedFileURL.path
            
            do {
                let attributes = try FileManager.default.attributesOfItem(atPath: recordedFileURL.path)
                if let fileSize = attributes[.size] as? NSNumber {
                    recordedAudioSize = fileSize.intValue
                    recordedAudioSizeFormatted = String(format: "%.1f", Double(fileSize.intValue) / 1024.0)
                    recordedAudioAvailable = true
                    logger.log("Found recorded audio file: \(recordedFileURL.path), size: \(fileSize.intValue) bytes", level: .debug)
                }
            } catch {
                logger.log("Error getting file attributes: \(error.localizedDescription)", level: .warning)
                recordedAudioAvailable = false
            }
        } else {
            recordedAudioSize = 0
            recordedAudioSizeFormatted = "0.0"
            recordedAudioAvailable = false
            recordedAudioPath = nil
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
                
                // Start recording using AudioRecorder instead of OpenAIManager
                self.audioRecorder.startRecording(microphoneID: deviceID)
                
                // Wait a small amount of time to check if recording actually started
                try await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
                
                // Update state on main thread when recording has started
                await MainActor.run {
                    self.isInitializingRecording = false
                    
                    if self.audioRecorder.isRecording {
                        self.logger.log("Recording started successfully", level: .info)
                        self.isRecordingAudio = true
                    } else {
                        self.lastError = "Failed to start recording"
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
        // Use our updated method that doesn't rely on buffer references
        stopAudioRecording()
    }
    
    // Transcribe the previously recorded audio
    func transcribeRecordedAudio() {
        guard !isRecordingAudio && !isTranscribing && !isInitializingRecording else { return }
        guard recordedAudioAvailable, let recordedFilePath = recordedAudioPath else {
            lastError = "No recorded audio file available"
            return
        }
        
        // Get API key from settings
        let apiKey = settingsManager.getCurrentAPIKey()
        
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
        
        // Get the current provider
        let providerType = settingsManager.getCurrentAIProvider()
        let provider = AIProviderFactory.getProvider(type: providerType)
        
        // Cancel any existing tasks
        transcriptionTask?.cancel()
        
        // Start time tracking for API response time
        let startTime = Date()
        
        // Create a reference to the audio file
        let recordedFileURL = URL(fileURLWithPath: recordedFilePath)
        
        // Start transcription task
        transcriptionTask = Task { [weak self] in
            guard let self = self else { return }
            
            do {
                // Process the audio and send it to the selected AI provider
                let result = await provider.transcribeAudio(
                    audioFileURL: recordedFileURL,
                    apiKey: apiKey,
                    model: selectedModel,
                    temperature: settingsManager.transcriptionTemperature,
                    language: "en"
                )
                
                // Calculate response time
                let responseTime = Date().timeIntervalSince(startTime)
                
                // Update the UI on the main thread
                await MainActor.run {
                    self.isTranscribing = false
                    self.apiResponseTime = responseTime
                    
                    switch result {
                    case .success(let text):
                        self.transcriptionText = text
                        self.statusText = "Transcription completed"
                        self.logger.log("Transcription successful: \(responseTime) seconds", level: .info)
                        
                    case .failure(let error):
                        self.statusText = "Transcription failed"
                        self.lastError = error.localizedDescription
                        self.logger.log("Transcription error: \(error)", level: .error)
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
    
    func stopAudioRecording() {
        // Guard against multiple calls to stopAudioRecording()
        guard isRecordingAudio else {
            logger.log("stopAudioRecording() called while not recording, ignoring", level: .debug)
            return
        }
        
        // Mark as not recording immediately to prevent multiple calls
        isRecordingAudio = false
        
        logger.log("Stopping audio recording...", level: .info)
        
        // Calculate actual recording duration before stopping
        let actualDuration = Date().timeIntervalSince(sessionStartTime ?? Date())
        let formattedDuration = String(format: "%.2f", actualDuration)
        
        // Stop the recording first
        audioRecorder.stopRecording()
        
        // Get the recorded file URL
        if let recordedFileURL = audioRecorder.getRecordingFileURL() {
            // Get file attributes
            do {
                let attributes = try FileManager.default.attributesOfItem(atPath: recordedFileURL.path)
                if let fileSize = attributes[.size] as? NSNumber {
                    recordedAudioSize = fileSize.intValue
                    recordedAudioDuration = actualDuration
                    recordedAudioDurationFormatted = formattedDuration
                    recordedAudioAvailable = true
                    recordedAudioPath = recordedFileURL.path
                    logger.log("Recorded audio saved: \(recordedAudioSize) bytes, \(recordedAudioDuration) seconds at \(recordedFileURL.path)", level: .info)
                }
            } catch {
                logger.log("Error getting recorded file attributes: \(error.localizedDescription)", level: .warning)
                recordedAudioAvailable = false
            }
        } else {
            logger.log("No recording file available after recording", level: .warning)
            recordedAudioAvailable = false
        }
        
        // Update UI state
        DispatchQueue.main.async {
            self.updateRecordedAudioInfo()
        }
        
        // Stop the session timer
        stopSessionTimer()
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
        
        // No need to call OpenAIManager.stopTranscription as it doesn't exist
        // and we're not handling streaming audio
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
            
            // Find and delete only our temp recording files
            for fileURL in fileURLs {
                if fileURL.lastPathComponent.starts(with: "recording_") {
                    try FileManager.default.removeItem(at: fileURL)
                    logger.log("Cleaned up previous recording file: \(fileURL.path)", level: .debug)
                }
            }
            
            logger.log("Temporary directory cleanup completed", level: .debug)
        } catch {
            logger.log("Error cleaning up temporary files: \(error.localizedDescription)", level: .warning)
        }
    }
    
    // Function to start a new transcription from recorded audio
    func captureAudioAndTranscribe() {
        isTranscribing = true
        sessionStartTime = Date()
        
        Task {
            do {
                guard let recordedFileURL = audioRecorder.getRecordingFileURL() else {
                    await MainActor.run {
                        errorMessage = "No recording file available"
                        isTranscribing = false
                    }
                    return
                }
                
                await MainActor.run {
                    recordedAudioPath = recordedFileURL.path
                }
                
                // Get file info for debugging
                do {
                    let attributes = try FileManager.default.attributesOfItem(atPath: recordedFileURL.path)
                    if let fileSize = attributes[.size] as? NSNumber {
                        await MainActor.run {
                            rawAudioSize = fileSize.intValue
                        }
                    }
                } catch {
                    logger.log("Error getting file attributes: \(error)", level: .warning)
                }
                
                // Get the current API key
                let apiKey = settingsManager.getCurrentAPIKey()
                
                // If we have an API key, proceed
                guard !apiKey.isEmpty else {
                    await MainActor.run {
                        errorMessage = "Please set your API key in settings"
                        isTranscribing = false
                    }
                    return
                }
                
                // Get the AI provider
                let providerType = settingsManager.getCurrentAIProvider()
                let provider = AIProviderFactory.getProvider(type: providerType)
                
                let startTime = Date()
                let result = await provider.transcribeAudio(
                    audioFileURL: recordedFileURL,
                    apiKey: apiKey,
                    model: selectedModel,
                    temperature: settingsManager.transcriptionTemperature,
                    language: "en"
                )
                
                let elapsed = Date().timeIntervalSince(startTime)
                
                // Process the result
                await MainActor.run {
                    transcriptionDuration = elapsed
                    
                    switch result {
                    case .success(let text):
                        transcribedText = text
                        errorMessage = ""
                    case .failure(let error):
                        errorMessage = "Error: \(error.localizedDescription)"
                        transcribedText = ""
                    }
                    
                    isTranscribing = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = "Error: \(error.localizedDescription)"
                    isTranscribing = false
                }
            }
        }
    }
} 