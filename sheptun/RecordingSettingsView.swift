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
        let debugInfo: String?  // Store debug information for errors
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                hotkeyConfigurationSection
                
                testTranscriptionSection
                
                recordingOptionsSection
                
                languageConfigurationSection
            }
            .padding(24)
        }
        .sheet(isPresented: $showingHotkeyRecorder) {
            HotkeyRecorder(
                initialKeyCode: settings.hotkeyKeyCode,
                initialModifiers: settings.hotkeyModifiers,
                onSave: { newKeyCode, newModifiers in
                    // Update settings with new values
                    settings.hotkeyKeyCode = newKeyCode
                    settings.hotkeyModifiers = newModifiers
                    settings.saveSettings()
                    
                    // Re-register hotkey with system
                    hotkeyManager.unregisterHotkey()
                    if newKeyCode != 0 && newModifiers != 0 {
                        let success = hotkeyManager.registerHotkey(
                            keyCode: newKeyCode,
                            modifiers: newModifiers
                        )
                        if success {
                            logger.log("Successfully registered new hotkey", level: .info)
                        } else {
                            logger.log("Failed to register new hotkey", level: .error)
                        }
                    }
                }
            )
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
            // Add a small delay to ensure the audio file is fully written
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
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
        
        // Use the centralized TranscriptionService
        let transcriptionService = TranscriptionService.shared
        let result = await transcriptionService.transcribeAudioFile(audioFileURL)
        
        DispatchQueue.main.async {
            self.isRecordingTest = false
            self.isTranscribing = false
            
            switch result {
            case .success(let transcriptionResult):
                let wordCount = transcriptionResult.text.split(separator: " ").count
                self.testResult = TestResult(
                    transcription: transcriptionResult.text,
                    duration: duration,
                    wordCount: wordCount,
                    timestamp: Date()
                )
                
                self.transcriptionHistory.insert(
                    TranscriptionEntry(
                        text: transcriptionResult.text,
                        timestamp: Date(),
                        duration: duration,
                        audioFileURL: nil,  // Success - no need to keep audio
                        isError: false,
                        provider: String(describing: transcriptionResult.provider),
                        model: transcriptionResult.model,
                        apiKey: nil,  // Don't store API key for successful transcriptions
                        debugInfo: nil
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
                
                // Get debug info from the service
                let debugInfo = transcriptionService.getDebugInfo() + """
                
                
                Audio File: \(audioFileURL.lastPathComponent)
                Error: \(error.localizedDescription)
                """
                
                self.transcriptionHistory.insert(
                    TranscriptionEntry(
                        text: "Error: \(error.localizedDescription)",
                        timestamp: Date(),
                        duration: duration,
                        audioFileURL: savedAudioURL,
                        isError: true,
                        provider: settings.selectedProvider,
                        model: settings.transcriptionModel,
                        apiKey: nil,  // Don't store API key
                        debugInfo: debugInfo
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
            let transcriptionService = TranscriptionService.shared
            let result = await transcriptionService.transcribeAudioFile(audioFileURL)
            
            DispatchQueue.main.async {
                self.isTranscribing = false
                
                switch result {
                case .success(let transcriptionResult):
                    // Update the entry in history
                    if let index = self.transcriptionHistory.firstIndex(where: { $0.id == entry.id }) {
                        self.transcriptionHistory[index] = TranscriptionEntry(
                            text: transcriptionResult.text,
                            timestamp: entry.timestamp,
                            duration: entry.duration,
                            audioFileURL: nil,  // Remove audio file after successful transcription
                            isError: false,
                            provider: String(describing: transcriptionResult.provider),
                            model: transcriptionResult.model,
                            apiKey: nil,
                            debugInfo: nil
                        )
                        
                        // Delete the audio file
                        try? FileManager.default.removeItem(at: audioFileURL)
                    }
                    
                case .failure(let error):
                    // Update error message
                    if let index = self.transcriptionHistory.firstIndex(where: { $0.id == entry.id }) {
                        let debugInfo = transcriptionService.getDebugInfo() + """
                        
                        
                        Audio File: \(audioFileURL.lastPathComponent)
                        Error: \(error.localizedDescription)
                        """
                        
                        self.transcriptionHistory[index] = TranscriptionEntry(
                            text: "Error: \(error.localizedDescription)",
                            timestamp: entry.timestamp,
                            duration: entry.duration,
                            audioFileURL: entry.audioFileURL,  // Keep audio file for another retry
                            isError: true,
                            provider: settings.selectedProvider,
                            model: settings.transcriptionModel,
                            apiKey: nil,
                            debugInfo: debugInfo
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
        // Use the same key mapping as HotkeyRecorder for consistency
        switch keyCode {
        case 0: return "A"
        case 1: return "S"
        case 2: return "D"
        case 3: return "F"
        case 4: return "H"
        case 5: return "G"
        case 6: return "Z"
        case 7: return "X"
        case 8: return "C"
        case 9: return "V"
        case 11: return "B"
        case 12: return "Q"
        case 13: return "W"
        case 14: return "E"
        case 15: return "R"
        case 16: return "Y"
        case 17: return "T"
        case 31: return "O"
        case 32: return "U"
        case 34: return "I"
        case 35: return "P"
        case 37: return "L"
        case 38: return "J"
        case 40: return "K"
        case 45: return "N"
        case 46: return "M"
        case 18: return "1"
        case 19: return "2"
        case 20: return "3"
        case 21: return "4"
        case 23: return "5"
        case 22: return "6"
        case 26: return "7"
        case 28: return "8"
        case 25: return "9"
        case 29: return "0"
        case 49: return "Space"
        case 36: return "Return"
        case 48: return "Tab"
        case 51: return "Delete"
        case 53: return "Escape"
        default: return NSEvent.keyCodeToString(keyCode: keyCode) ?? "Key\(keyCode)"
        }
    }
}

struct TestResultView: View {
    let result: RecordingSettingsView.TestResult
    @State private var showingFullText = false
    @StateObject private var settings = SettingsManager.shared
    
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
                    VStack(alignment: .leading, spacing: 16) {
                        Text(result.transcription)
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                        
                        if result.transcription.hasPrefix("Error:") {
                            Divider()
                            
                            Text("Debug Information")
                                .font(.headline)
                                .padding(.top)
                            
                            Text("""
                            Provider: \(settings.selectedProvider)
                            Model: \(settings.transcriptionModel)
                            Language: \(settings.transcriptionLanguage)
                            Temperature: \(settings.transcriptionTemperature)
                            """)
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                        }
                    }
                    .padding()
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