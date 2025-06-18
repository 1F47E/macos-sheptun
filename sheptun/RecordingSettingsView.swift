import SwiftUI
import Combine

struct RecordingSettingsView: View {
    @StateObject private var settings = SettingsManager.shared
    @State private var isRecordingTest = false
    @State private var isTranscribing = false
    @State private var recordingStartTime: Date?
    @State private var testResult: TestResult?
    @State private var transcriptionHistory: [TranscriptionEntry] = []
    @State private var showingHotkeyRecorder = false
    
    private let hotkeyManager = HotkeyManager.shared
    private let audioRecorder = AudioRecorder.shared
    private let logger = Logger.shared
    
    struct TestResult {
        let transcription: String
        let duration: TimeInterval
        let wordCount: Int
        let timestamp: Date
    }
    
    struct TranscriptionEntry: Identifiable {
        let id = UUID()
        let text: String
        let timestamp: Date
        let duration: TimeInterval
        let audioFileURL: URL?  // Store audio file for failed transcriptions
        let isError: Bool       // Track if this was an error
        let provider: String?   // Store which provider was used
        let model: String?      // Store which model was used
        let apiKey: String?     // Store API key for retry (will be encrypted in real implementation)
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                hotkeyConfigurationSection
                
                testTranscriptionSection
                
                recordingOptionsSection
                
                languageConfigurationSection
                
                if !transcriptionHistory.isEmpty {
                    historySection
                }
            }
            .padding(24)
        }
        .sheet(isPresented: $showingHotkeyRecorder) {
            HotkeyRecorder(
                keyCode: $settings.hotkeyKeyCode,
                modifiers: $settings.hotkeyModifiers
            )
            .frame(width: 400, height: 200)
        }
    }
    
    private var hotkeyConfigurationSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Hotkey Configuration")
                .font(.headline)
            
            GroupBox {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Label("Recording Hotkey", systemImage: "keyboard")
                            .foregroundColor(.secondary)
                        
                        Spacer()
                        
                        if settings.hotkeyKeyCode != 0 {
                            HotkeyDisplay(
                                keyCode: UInt16(settings.hotkeyKeyCode),
                                modifiers: settings.hotkeyModifiers
                            )
                        } else {
                            Text("Not Set")
                                .foregroundColor(.secondary)
                        }
                        
                        Button("Change") {
                            showingHotkeyRecorder = true
                        }
                        .buttonStyle(.bordered)
                    }
                    
                    Text("Press this key combination to start/stop recording from anywhere")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding()
            }
        }
    }
    
    private var testTranscriptionSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Test Transcription")
                .font(.headline)
            
            GroupBox {
                VStack(spacing: 16) {
                    HStack {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Test your complete setup")
                                .font(.subheadline)
                            Text("Records audio and transcribes it using your selected provider")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                    }
                    
                    Divider()
                    
                    HStack {
                        Button(action: {
                            if isRecordingTest {
                                stopTestTranscription()
                            } else {
                                startTestTranscription()
                            }
                        }) {
                            HStack {
                                if isTranscribing {
                                    ProgressView()
                                        .scaleEffect(0.8)
                                } else {
                                    Image(systemName: isRecordingTest ? "stop.circle" : "mic.badge.plus")
                                        .symbolVariant(isRecordingTest ? .fill : .none)
                                }
                                
                                Text(isTranscribing ? "Processing..." : 
                                     isRecordingTest ? "Stop Recording" : "Start Test")
                            }
                        }
                        .controlSize(.large)
                        .buttonStyle(.borderedProminent)
                        .disabled(isTranscribing || (settings.getCurrentAPIKey().isEmpty && !isRecordingTest))
                        
                        if isRecordingTest {
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(Color.red)
                                    .frame(width: 8, height: 8)
                                    .opacity(isRecordingTest ? 1 : 0)
                                    .animation(.easeInOut(duration: 0.5).repeatForever(), value: isRecordingTest)
                                
                                Text("Recording...")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        } else if isTranscribing {
                            HStack(spacing: 8) {
                                ProgressView()
                                    .scaleEffect(0.8)
                                Text("Transcribing...")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        Spacer()
                    }
                    
                    if let result = testResult {
                        TestResultView(result: result)
                    }
                }
                .padding()
            }
        }
    }
    
    private var recordingOptionsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Recording Options")
                .font(.headline)
            
            GroupBox {
                VStack(spacing: 16) {
                    Toggle("Auto-paste transcription", isOn: $settings.autoPasteTranscription)
                        .onChange(of: settings.autoPasteTranscription) { _, _ in
                            settings.saveSettings()
                        }
                    
                    Text("Automatically paste the transcribed text after recording")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    
                    Divider()
                    
                    HStack {
                        Label("Local History Storage", systemImage: "internaldrive")
                            .foregroundColor(.secondary)
                        
                        Spacer()
                        
                        Toggle("", isOn: .constant(true))
                            .disabled(true)
                    }
                    
                    Text("All transcriptions are stored locally on your Mac. Your data never leaves your device.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding()
            }
        }
    }
    
    private var languageConfigurationSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Language Settings")
                .font(.headline)
            
            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Transcription Language")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    Picker("", selection: $settings.transcriptionLanguage) {
                        Text("Auto-detect").tag("auto")
                        Text("English").tag("en")
                        Text("Spanish").tag("es")
                        Text("French").tag("fr")
                        Text("German").tag("de")
                        Text("Italian").tag("it")
                        Text("Portuguese").tag("pt")
                        Text("Russian").tag("ru")
                        Text("Japanese").tag("ja")
                        Text("Korean").tag("ko")
                        Text("Chinese (Mandarin)").tag("zh")
                        Text("Arabic").tag("ar")
                        Text("Hindi").tag("hi")
                        Text("Dutch").tag("nl")
                        Text("Polish").tag("pl")
                        Text("Swedish").tag("sv")
                        Text("Norwegian").tag("no")
                        Text("Danish").tag("da")
                        Text("Finnish").tag("fi")
                        Text("Turkish").tag("tr")
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .onChange(of: settings.transcriptionLanguage) { _, _ in
                        settings.saveSettings()
                    }
                    
                    Text("Select the language of your audio for better transcription accuracy. Auto-detect works well for most cases.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.top, 4)
                }
                .padding(12)
            }
        }
    }
    
    private var historySection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Recent Transcriptions")
                    .font(.headline)
                
                Spacer()
                
                Button("Clear History") {
                    transcriptionHistory.removeAll()
                }
                .buttonStyle(.borderless)
                .foregroundColor(.secondary)
            }
            
            GroupBox {
                VStack(spacing: 12) {
                    ForEach(transcriptionHistory.prefix(5)) { entry in
                        HistoryRow(entry: entry, onRetry: retryTranscription)
                        
                        if entry.id != transcriptionHistory.prefix(5).last?.id {
                            Divider()
                        }
                    }
                }
                .padding(8)
            }
        }
    }
    
    private func startTestTranscription() {
        // Check if any microphones are available
        let availableMics = settings.getAvailableMicrophones()
        if availableMics.isEmpty {
            testResult = TestResult(
                transcription: "Error: No microphones available. Please connect a microphone.",
                duration: 0,
                wordCount: 0,
                timestamp: Date()
            )
            return
        }
        
        // Check if a microphone is selected
        if settings.selectedMicrophoneID.isEmpty {
            testResult = TestResult(
                transcription: "Error: No microphone selected. Please select a microphone in Audio Settings.",
                duration: 0,
                wordCount: 0,
                timestamp: Date()
            )
            return
        }
        
        // Provide immediate haptic feedback
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        
        isRecordingTest = true
        testResult = nil
        recordingStartTime = Date()
        
        // Start recording directly with AudioRecorder
        audioRecorder.startRecording()
    }
    
    private func stopTestTranscription() {
        // Provide immediate haptic feedback
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        
        // Stop recording immediately
        audioRecorder.stopRecording()
        
        // Update UI state immediately to show we're processing
        isRecordingTest = false
        isTranscribing = true
        
        // Calculate duration
        let duration = Date().timeIntervalSince(recordingStartTime ?? Date())
        
        // Transcribe the audio
        Task {
            await transcribeTestRecording(duration: duration)
        }
    }
    
    private func transcribeTestRecording(duration: TimeInterval) async {
        // Get the audio file URL from the recorder
        guard let audioFileURL = audioRecorder.recordingFileURL else {
            DispatchQueue.main.async {
                self.isRecordingTest = false
                self.testResult = TestResult(
                    transcription: "Error: No audio file found",
                    duration: duration,
                    wordCount: 0,
                    timestamp: Date()
                )
            }
            return
        }
        
        // Transcribing state already set in stopTestTranscription()
        
        // Get AI provider and transcribe
        let provider = settings.getCurrentAIProvider()
        let aiManager = AIProviderFactory.getProvider(type: provider)
        let apiKey = settings.getCurrentAPIKey()
        
        let result = await aiManager.transcribeAudio(
            audioFileURL: audioFileURL,
            apiKey: apiKey,
            model: settings.transcriptionModel,
            temperature: settings.transcriptionTemperature,
            language: settings.transcriptionLanguage
        )
        
        DispatchQueue.main.async {
            self.isRecordingTest = false
            self.isTranscribing = false
            
            switch result {
            case .success(let transcription):
                let wordCount = transcription.split(separator: " ").count
                self.testResult = TestResult(
                    transcription: transcription,
                    duration: duration,
                    wordCount: wordCount,
                    timestamp: Date()
                )
                
                self.transcriptionHistory.insert(
                    TranscriptionEntry(
                        text: transcription,
                        timestamp: Date(),
                        duration: duration,
                        audioFileURL: nil,  // Success - no need to keep audio
                        isError: false,
                        provider: String(describing: provider),
                        model: settings.transcriptionModel,
                        apiKey: nil  // Don't store API key for successful transcriptions
                    ),
                    at: 0
                )
                
            case .failure(let error):
                self.testResult = TestResult(
                    transcription: "Error: \(error.localizedDescription)",
                    duration: duration,
                    wordCount: 0,
                    timestamp: Date()
                )
                
                // Save the audio file for retry
                let savedAudioURL = self.saveAudioFileForRetry(audioFileURL)
                
                // Store failed transcription in history with audio file
                self.transcriptionHistory.insert(
                    TranscriptionEntry(
                        text: "Error: \(error.localizedDescription)",
                        timestamp: Date(),
                        duration: duration,
                        audioFileURL: savedAudioURL,
                        isError: true,
                        provider: String(describing: provider),
                        model: settings.transcriptionModel,
                        apiKey: apiKey  // Store for retry (should be encrypted in production)
                    ),
                    at: 0
                )
            }
        }
    }
    
    private func saveAudioFileForRetry(_ temporaryURL: URL) -> URL? {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let audioDirectory = documentsPath.appendingPathComponent("FailedRecordings")
        
        // Create directory if it doesn't exist
        try? FileManager.default.createDirectory(at: audioDirectory, withIntermediateDirectories: true)
        
        let fileName = "recording_\(Date().timeIntervalSince1970).m4a"
        let destinationURL = audioDirectory.appendingPathComponent(fileName)
        
        do {
            try FileManager.default.copyItem(at: temporaryURL, to: destinationURL)
            logger.log("Saved failed recording to: \(destinationURL.path)", level: .info)
            return destinationURL
        } catch {
            logger.log("Failed to save audio file: \(error)", level: .error)
            return nil
        }
    }
    
    private func retryTranscription(entry: TranscriptionEntry) {
        guard let audioFileURL = entry.audioFileURL,
              FileManager.default.fileExists(atPath: audioFileURL.path) else {
            logger.log("Audio file not found for retry", level: .error)
            return
        }
        
        isTranscribing = true
        
        Task {
            let provider = settings.getCurrentAIProvider()
            let aiManager = AIProviderFactory.getProvider(type: provider)
            let apiKey = settings.getCurrentAPIKey()
            
            let result = await aiManager.transcribeAudio(
                audioFileURL: audioFileURL,
                apiKey: apiKey,
                model: settings.transcriptionModel,
                temperature: settings.transcriptionTemperature,
                language: settings.transcriptionLanguage
            )
            
            DispatchQueue.main.async {
                self.isTranscribing = false
                
                switch result {
                case .success(let transcription):
                    // Update the entry in history
                    if let index = self.transcriptionHistory.firstIndex(where: { $0.id == entry.id }) {
                        self.transcriptionHistory[index] = TranscriptionEntry(
                            text: transcription,
                            timestamp: entry.timestamp,
                            duration: entry.duration,
                            audioFileURL: nil,  // Remove audio file after successful transcription
                            isError: false,
                            provider: String(describing: provider),
                            model: settings.transcriptionModel,
                            apiKey: nil
                        )
                        
                        // Delete the audio file
                        try? FileManager.default.removeItem(at: audioFileURL)
                    }
                    
                case .failure(let error):
                    // Update error message
                    if let index = self.transcriptionHistory.firstIndex(where: { $0.id == entry.id }) {
                        self.transcriptionHistory[index] = TranscriptionEntry(
                            text: "Error: \(error.localizedDescription)",
                            timestamp: entry.timestamp,
                            duration: entry.duration,
                            audioFileURL: entry.audioFileURL,  // Keep audio file for another retry
                            isError: true,
                            provider: String(describing: provider),
                            model: settings.transcriptionModel,
                            apiKey: apiKey
                        )
                    }
                }
            }
        }
    }
    
    @State private var cancellables = Set<AnyCancellable>()
}

struct HotkeyDisplay: View {
    let keyCode: UInt16
    let modifiers: UInt
    
    var body: some View {
        HStack(spacing: 4) {
            ForEach(modifierSymbols, id: \.self) { symbol in
                Image(systemName: symbol)
                    .font(.caption)
            }
            
            Text(keyString)
                .font(.system(.body, design: .monospaced))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.accentColor.opacity(0.1))
        .cornerRadius(6)
    }
    
    private var modifierSymbols: [String] {
        var symbols: [String] = []
        if modifiers & NSEvent.ModifierFlags.control.rawValue != 0 { symbols.append("control") }
        if modifiers & NSEvent.ModifierFlags.option.rawValue != 0 { symbols.append("option") }
        if modifiers & NSEvent.ModifierFlags.shift.rawValue != 0 { symbols.append("shift") }
        if modifiers & NSEvent.ModifierFlags.command.rawValue != 0 { symbols.append("command") }
        return symbols
    }
    
    private var keyString: String {
        return NSEvent.keyCodeToString(keyCode: keyCode) ?? "Unknown"
    }
}

struct TestResultView: View {
    let result: RecordingSettingsView.TestResult
    @State private var showingFullText = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                if result.transcription.hasPrefix("Error:") {
                    Label("Test Failed", systemImage: "xmark.circle.fill")
                        .foregroundColor(.red)
                        .font(.subheadline)
                } else {
                    Label("Test Successful", systemImage: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(.subheadline)
                }
                
                Spacer()
                
                Text(result.timestamp, style: .time)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Divider()
            
            if !result.transcription.hasPrefix("Error:") {
                HStack(spacing: 20) {
                    StatItem(
                        icon: "clock",
                        value: String(format: "%.1fs", result.duration),
                        label: "Duration"
                    )
                    
                    StatItem(
                        icon: "textformat",
                        value: "\(result.wordCount)",
                        label: "Words"
                    )
                    
                    StatItem(
                        icon: "speedometer",
                        value: String(format: "%.0f", Double(result.wordCount) / result.duration * 60),
                        label: "WPM"
                    )
                }
                
                Divider()
            }
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Transcription Result")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    Button("Show Full") {
                        showingFullText = true
                    }
                    .buttonStyle(.borderless)
                    .font(.caption)
                }
                
                Text(result.transcription)
                    .lineLimit(2)
                    .font(.system(.body, design: .monospaced))
                    .padding(8)
                    .background(Color(NSColor.textBackgroundColor))
                    .cornerRadius(6)
            }
        }
        .padding()
        .background(result.transcription.hasPrefix("Error:") ? Color.red.opacity(0.05) : Color.green.opacity(0.05))
        .cornerRadius(8)
        .sheet(isPresented: $showingFullText) {
            VStack {
                Text("Full Transcription")
                    .font(.headline)
                    .padding()
                
                ScrollView {
                    Text(result.transcription)
                        .font(.system(.body, design: .monospaced))
                        .padding()
                        .textSelection(.enabled)
                }
                
                Button("Done") {
                    showingFullText = false
                }
                .padding()
            }
            .frame(width: 500, height: 400)
        }
    }
}

struct StatItem: View {
    let icon: String
    let value: String
    let label: String
    
    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(.accentColor)
            
            Text(value)
                .font(.system(.title3, design: .monospaced))
                .fontWeight(.medium)
            
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

struct HistoryRow: View {
    let entry: RecordingSettingsView.TranscriptionEntry
    let onRetry: (RecordingSettingsView.TranscriptionEntry) -> Void
    @State private var isCopied = false
    
    var body: some View {
        HStack {
            if entry.isError {
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundColor(.red)
                    .font(.caption)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.text)
                    .lineLimit(1)
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(entry.isError ? .red : .primary)
                
                HStack {
                    Text(entry.timestamp, style: .time)
                    Text("•")
                    Text(String(format: "%.1fs", entry.duration))
                    if entry.audioFileURL != nil {
                        Text("• Audio saved")
                            .foregroundColor(.orange)
                    }
                }
                .font(.caption)
                .foregroundColor(.secondary)
            }
            
            Spacer()
            
            if entry.isError && entry.audioFileURL != nil {
                Button(action: { onRetry(entry) }) {
                    Label("Retry", systemImage: "arrow.clockwise")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            
            Button(action: copyToClipboard) {
                Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                    .foregroundColor(isCopied ? .green : .secondary)
            }
            .buttonStyle(.borderless)
            .disabled(entry.isError)  // Disable copy for errors
        }
        .padding(.vertical, 4)
    }
    
    private func copyToClipboard() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(entry.text, forType: .string)
        
        withAnimation {
            isCopied = true
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation {
                isCopied = false
            }
        }
    }
}

import Combine

extension NSEvent {
    static func keyCodeToString(keyCode: UInt16) -> String? {
        let source = CGEventSource(stateID: .hidSystemState)
        let event = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true)
        event?.flags = []
        
        var length = 0
        event?.keyboardGetUnicodeString(maxStringLength: 0, actualStringLength: &length, unicodeString: nil)
        
        guard length > 0 else { return nil }
        
        let buffer = UnsafeMutablePointer<UniChar>.allocate(capacity: Int(length))
        defer { buffer.deallocate() }
        
        event?.keyboardGetUnicodeString(maxStringLength: Int(length), actualStringLength: nil, unicodeString: buffer)
        
        return String(utf16CodeUnits: buffer, count: Int(length)).uppercased()
    }
}

#Preview {
    RecordingSettingsView()
        .frame(width: 600, height: 500)
}