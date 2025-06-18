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
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                hotkeyConfigurationSection
                
                testTranscriptionSection
                
                recordingOptionsSection
                
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
                                Image(systemName: isRecordingTest ? "stop.circle" : "mic.badge.plus")
                                    .symbolVariant(isRecordingTest ? .fill : .none)
                                Text(isRecordingTest ? "Stop Recording" : "Start Test")
                            }
                        }
                        .controlSize(.large)
                        .buttonStyle(.borderedProminent)
                        .disabled((isTranscribing || settings.getCurrentAPIKey().isEmpty) && !isRecordingTest)
                        
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
                        HistoryRow(entry: entry)
                        
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
        isRecordingTest = true
        testResult = nil
        recordingStartTime = Date()
        
        // Start recording directly with AudioRecorder
        audioRecorder.startRecording()
    }
    
    private func stopTestTranscription() {
        // Stop recording
        audioRecorder.stopRecording()
        
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
        
        // Show transcribing state
        DispatchQueue.main.async {
            self.isTranscribing = true
        }
        
        // Get AI provider and transcribe
        let provider = settings.getCurrentAIProvider()
        let aiManager = AIProviderFactory.getProvider(type: provider)
        let apiKey = settings.getCurrentAPIKey()
        
        let result = await aiManager.transcribeAudio(
            audioFileURL: audioFileURL,
            apiKey: apiKey,
            model: settings.transcriptionModel,
            temperature: settings.transcriptionTemperature,
            language: "en"
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
                        duration: duration
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
                Label("Test Successful", systemImage: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .font(.subheadline)
                
                Spacer()
                
                Text(result.timestamp, style: .time)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Divider()
            
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
        .background(Color.green.opacity(0.05))
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
    @State private var isCopied = false
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.text)
                    .lineLimit(1)
                    .font(.system(.body, design: .monospaced))
                
                HStack {
                    Text(entry.timestamp, style: .time)
                    Text("•")
                    Text(String(format: "%.1fs", entry.duration))
                }
                .font(.caption)
                .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Button(action: copyToClipboard) {
                Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                    .foregroundColor(isCopied ? .green : .secondary)
            }
            .buttonStyle(.borderless)
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