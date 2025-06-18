import SwiftUI
import Combine

struct HistoryView: View {
    @StateObject private var settings = SettingsManager.shared
    @State private var transcriptionHistory: [RecordingSettingsView.TranscriptionEntry] = []
    @State private var showingClearConfirmation = false
    @State private var isRetrying = false
    @State private var selectedEntry: RecordingSettingsView.TranscriptionEntry?
    
    private let logger = Logger.shared
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                historySettingsSection
                
                if !transcriptionHistory.isEmpty {
                    historyStatisticsSection
                    historyListSection
                } else {
                    emptyHistoryView
                }
            }
            .padding(24)
        }
        .onAppear {
            loadTranscriptionHistory()
        }
    }
    
    private var historySettingsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("History Settings")
                .font(.headline)
            
            GroupBox {
                VStack(spacing: 16) {
                    HStack {
                        Label("Enable History Storage", systemImage: "internaldrive")
                            .foregroundColor(.secondary)
                        
                        Spacer()
                        
                        Toggle("", isOn: $settings.enableHistoryStorage)
                            .onChange(of: settings.enableHistoryStorage) { _, _ in
                                settings.saveSettings()
                            }
                    }
                    
                    Text("Store all transcriptions locally on your Mac. Your data never leaves your device.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    
                    if settings.enableHistoryStorage {
                        Divider()
                        
                        HStack {
                            Text("Failed recordings are automatically saved for retry")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            Spacer()
                            
                            Image(systemName: "info.circle")
                                .foregroundColor(.secondary)
                                .help("When a transcription fails, the audio file is saved so you can retry later without losing your recording")
                        }
                    }
                }
                .padding()
            }
        }
    }
    
    private var historyStatisticsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Statistics")
                .font(.headline)
            
            GroupBox {
                HStack(spacing: 20) {
                    StatisticItem(
                        icon: "doc.text",
                        value: "\(transcriptionHistory.count)",
                        label: "Total",
                        color: .blue
                    )
                    
                    StatisticItem(
                        icon: "checkmark.circle",
                        value: "\(successfulTranscriptions)",
                        label: "Successful",
                        color: .green
                    )
                    
                    StatisticItem(
                        icon: "exclamationmark.triangle",
                        value: "\(failedTranscriptions)",
                        label: "Failed",
                        color: .red
                    )
                    
                    StatisticItem(
                        icon: "arrow.clockwise",
                        value: "\(retriableTranscriptions)",
                        label: "Retriable",
                        color: .orange
                    )
                }
                .padding(8)
            }
        }
    }
    
    private var historyListSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Transcription History")
                    .font(.headline)
                
                Spacer()
                
                Button(action: {
                    showingClearConfirmation = true
                }) {
                    Label("Clear All", systemImage: "trash")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                .foregroundColor(.red)
            }
            
            GroupBox {
                VStack(spacing: 12) {
                    ForEach(transcriptionHistory) { entry in
                        HistoryItemRow(
                            entry: entry,
                            isRetrying: isRetrying && selectedEntry?.id == entry.id,
                            onRetry: { retryTranscription(entry) },
                            onDelete: { deleteEntry(entry) }
                        )
                        
                        if entry.id != transcriptionHistory.last?.id {
                            Divider()
                        }
                    }
                }
                .padding(8)
            }
        }
        .confirmationDialog(
            "Clear All History",
            isPresented: $showingClearConfirmation,
            titleVisibility: .visible
        ) {
            Button("Clear All", role: .destructive) {
                clearAllHistory()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently delete all transcription history. Failed recordings with saved audio files will also be deleted.")
        }
    }
    
    private var emptyHistoryView: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            
            Text("No Transcription History")
                .font(.headline)
                .foregroundColor(.secondary)
            
            Text("Your transcription history will appear here")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 200)
        .padding()
    }
    
    // MARK: - Helper Properties
    
    private var successfulTranscriptions: Int {
        transcriptionHistory.filter { !$0.isError }.count
    }
    
    private var failedTranscriptions: Int {
        transcriptionHistory.filter { $0.isError }.count
    }
    
    private var retriableTranscriptions: Int {
        transcriptionHistory.filter { $0.isError && $0.audioFileURL != nil }.count
    }
    
    // MARK: - Actions
    
    private func loadTranscriptionHistory() {
        // TODO: Load from persistent storage when database is implemented
        // For now, this is just a placeholder
        logger.log("Loading transcription history", level: .debug)
    }
    
    private func retryTranscription(_ entry: RecordingSettingsView.TranscriptionEntry) {
        guard let audioFileURL = entry.audioFileURL,
              FileManager.default.fileExists(atPath: audioFileURL.path) else {
            logger.log("Audio file not found for retry", level: .error)
            return
        }
        
        isRetrying = true
        selectedEntry = entry
        
        Task {
            let transcriptionService = TranscriptionService.shared
            let result = await transcriptionService.transcribeAudioFile(audioFileURL)
            
            DispatchQueue.main.async {
                self.isRetrying = false
                self.selectedEntry = nil
                
                switch result {
                case .success(let transcriptionResult):
                    // Update the entry in history
                    if let index = self.transcriptionHistory.firstIndex(where: { $0.id == entry.id }) {
                        self.transcriptionHistory[index] = RecordingSettingsView.TranscriptionEntry(
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
                        
                        self.transcriptionHistory[index] = RecordingSettingsView.TranscriptionEntry(
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
    
    private func deleteEntry(_ entry: RecordingSettingsView.TranscriptionEntry) {
        // Delete audio file if it exists
        if let audioFileURL = entry.audioFileURL {
            try? FileManager.default.removeItem(at: audioFileURL)
        }
        
        // Remove from history
        transcriptionHistory.removeAll { $0.id == entry.id }
    }
    
    private func clearAllHistory() {
        // Delete all audio files
        for entry in transcriptionHistory {
            if let audioFileURL = entry.audioFileURL {
                try? FileManager.default.removeItem(at: audioFileURL)
            }
        }
        
        // Clear history
        transcriptionHistory.removeAll()
        
        // TODO: Clear from persistent storage when database is implemented
    }
}

struct StatisticItem: View {
    let icon: String
    let value: String
    let label: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(color)
            
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

struct HistoryItemRow: View {
    let entry: RecordingSettingsView.TranscriptionEntry
    let isRetrying: Bool
    let onRetry: () -> Void
    let onDelete: () -> Void
    
    @State private var isCopied = false
    @State private var showingDeleteConfirmation = false
    
    var body: some View {
        HStack {
            // Status icon
            if entry.isError {
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundColor(.red)
                    .font(.caption)
            } else {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .font(.caption)
            }
            
            // Content
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.text)
                    .lineLimit(2)
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(entry.isError ? .red : .primary)
                
                HStack {
                    Text(entry.timestamp, style: .date)
                    Text("•")
                    Text(entry.timestamp, style: .time)
                    Text("•")
                    Text(String(format: "%.1fs", entry.duration))
                    if let provider = entry.provider {
                        Text("•")
                        Text(provider.capitalized)
                            .font(.caption)
                    }
                    if entry.audioFileURL != nil {
                        Text("• Audio saved")
                            .foregroundColor(.orange)
                    }
                }
                .font(.caption)
                .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // Actions
            HStack(spacing: 8) {
                if entry.isError && entry.audioFileURL != nil {
                    Button(action: onRetry) {
                        if isRetrying {
                            ProgressView()
                                .scaleEffect(0.8)
                        } else {
                            Label("Retry", systemImage: "arrow.clockwise")
                                .font(.caption)
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(isRetrying)
                }
                
                if !entry.isError {
                    Button(action: copyToClipboard) {
                        Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                            .foregroundColor(isCopied ? .green : .secondary)
                    }
                    .buttonStyle(.borderless)
                }
                
                Button(action: { showingDeleteConfirmation = true }) {
                    Image(systemName: "trash")
                        .foregroundColor(.red.opacity(0.7))
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(.vertical, 4)
        .confirmationDialog(
            "Delete Entry",
            isPresented: $showingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                onDelete()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            if entry.audioFileURL != nil {
                Text("This will delete the transcription and its saved audio file.")
            } else {
                Text("This will delete the transcription from history.")
            }
        }
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

#Preview {
    HistoryView()
        .frame(width: 600, height: 500)
}