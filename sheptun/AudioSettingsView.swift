import SwiftUI
import AVFoundation

struct AudioSettingsView: View {
    @StateObject private var settings = SettingsManager.shared
    @State private var availableMicrophones: [SettingsManager.MicrophoneDevice] = []
    @State private var audioLevel: Float = 0
    @State private var audioMonitor: AudioLevelMonitor? = nil
    @State private var audioMonitorError: String? = nil
    @State private var isTestingAudio = false
    @State private var testRecordingURL: URL? = nil
    
    private let logger = Logger.shared
    private let audioRecorder = AudioRecorder.shared
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                microphoneSelectionSection
                
                audioLevelSection
                
                audioQualitySection
                
                testRecordingSection
            }
            .padding(24)
        }
        .onAppear {
            availableMicrophones = settings.getAvailableMicrophones()
            logger.log("Loaded \(availableMicrophones.count) microphones for AudioSettingsView")
            
            if !settings.selectedMicrophoneID.isEmpty {
                startAudioMonitoring(deviceID: settings.selectedMicrophoneID)
            }
        }
        .onDisappear {
            stopAudioMonitoring()
        }
    }
    
    private var microphoneSelectionSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Input Device")
                .font(.headline)
            
            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    if availableMicrophones.isEmpty {
                        HStack {
                            Image(systemName: "mic.slash")
                                .font(.title2)
                                .foregroundColor(.red)
                            
                            VStack(alignment: .leading) {
                                Text("No microphones found")
                                    .font(.headline)
                                Text("Please connect a microphone to use Sheptun")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                        }
                        .padding()
                    } else {
                        ForEach(availableMicrophones) { mic in
                            MicrophoneRow(
                                device: mic,
                                isSelected: settings.selectedMicrophoneID == mic.id,
                                action: {
                                    settings.selectedMicrophoneID = mic.id
                                    settings.saveSettings()
                                    startAudioMonitoring(deviceID: mic.id)
                                }
                            )
                        }
                    }
                }
                .padding(8)
            }
        }
    }
    
    private var audioLevelSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Audio Level Monitor")
                .font(.headline)
            
            GroupBox {
                VStack(spacing: 16) {
                    if let error = audioMonitorError {
                        HStack {
                            Image(systemName: "exclamationmark.triangle")
                                .foregroundColor(.orange)
                            Text("Monitor Error: \(error)")
                                .font(.caption)
                            Spacer()
                        }
                        .padding(.horizontal)
                    }
                    
                    AudioWaveformView(audioLevel: audioLevel)
                        .frame(height: 80)
                        .padding(.horizontal)
                    
                    HStack {
                        Label("Silent", systemImage: "speaker.slash")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Spacer()
                        
                        Text(String(format: "%.0f%%", audioLevel * 100))
                            .font(.system(.caption, design: .monospaced))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(levelColor.opacity(0.2))
                            .cornerRadius(4)
                        
                        Spacer()
                        
                        Label("Loud", systemImage: "speaker.wave.3")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal)
                }
                .padding(.vertical, 12)
            }
        }
    }
    
    private var audioQualitySection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Audio Quality")
                .font(.headline)
            
            GroupBox {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Label("Sample Rate", systemImage: "waveform.path")
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("48 kHz")
                            .font(.system(.body, design: .monospaced))
                    }
                    
                    Divider()
                    
                    HStack {
                        Label("Format", systemImage: "doc.badge.waveform")
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("Linear PCM")
                            .font(.system(.body, design: .monospaced))
                    }
                    
                    Divider()
                    
                    HStack {
                        Label("Channels", systemImage: "dot.radiowaves.left.and.right")
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("Mono")
                            .font(.system(.body, design: .monospaced))
                    }
                }
                .padding()
            }
        }
    }
    
    private var testRecordingSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Test Recording")
                .font(.headline)
            
            GroupBox {
                VStack(spacing: 16) {
                    Text("Test your microphone setup with a quick recording")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    HStack {
                        Button(action: toggleTestRecording) {
                            HStack {
                                Image(systemName: isTestingAudio ? "stop.circle" : "mic.circle")
                                    .symbolVariant(isTestingAudio ? .fill : .none)
                                Text(isTestingAudio ? "Stop Recording" : "Start Test Recording")
                            }
                        }
                        .controlSize(.large)
                        .buttonStyle(.borderedProminent)
                        .disabled(availableMicrophones.isEmpty)
                        
                        if isTestingAudio {
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(Color.red)
                                    .frame(width: 8, height: 8)
                                    .opacity(isTestingAudio ? 1 : 0)
                                    .animation(.easeInOut(duration: 0.5).repeatForever(), value: isTestingAudio)
                                
                                Text("Recording...")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        Spacer()
                    }
                    
                    if let url = testRecordingURL {
                        TestRecordingPlayer(url: url)
                    }
                }
                .padding()
            }
        }
    }
    
    private var levelColor: Color {
        if audioLevel < 0.5 {
            return .green
        } else if audioLevel < 0.8 {
            return .yellow
        } else {
            return .red
        }
    }
    
    private func toggleTestRecording() {
        if isTestingAudio {
            stopTestRecording()
        } else {
            startTestRecording()
        }
    }
    
    private func startTestRecording() {
        isTestingAudio = true
        testRecordingURL = nil
        
        audioRecorder.startRecording()
        
        // Stop recording after 3 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            if isTestingAudio {
                stopTestRecording()
            }
        }
    }
    
    private func stopTestRecording() {
        isTestingAudio = false
        audioRecorder.stopRecording()
        
        // For now, we'll just clear the test recording URL
        // In a real implementation, we'd need to get the URL from the recorder
        testRecordingURL = nil
    }
    
    private func startAudioMonitoring(deviceID: String) {
        stopAudioMonitoring()
        
        if let numericID = UInt32(deviceID) {
            audioMonitor = AudioLevelMonitor(deviceID: numericID)
            audioMonitor?.startMonitoring(
                levelUpdateHandler: { level in
                    DispatchQueue.main.async {
                        self.audioLevel = (self.audioLevel * 0.7) + (level * 0.3)
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
            logger.log("Failed to start audio monitoring: Invalid device ID format '\(deviceID)'", level: .error)
            audioMonitorError = "Invalid device ID format"
        }
    }
    
    private func stopAudioMonitoring() {
        audioMonitor?.stopMonitoring()
        audioMonitor = nil
        DispatchQueue.main.async {
            self.audioLevel = 0
        }
    }
}

struct MicrophoneRow: View {
    let device: SettingsManager.MicrophoneDevice
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: "mic")
                    .font(.title2)
                    .foregroundColor(isSelected ? .accentColor : .secondary)
                
                VStack(alignment: .leading) {
                    Text(device.name)
                        .font(.body)
                        .foregroundColor(.primary)
                    
                    Text("ID: \(device.id)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.accentColor)
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(isSelected ? Color.accentColor : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

struct AudioWaveformView: View {
    let audioLevel: Float
    @State private var phase: CGFloat = 0
    
    var body: some View {
        GeometryReader { geometry in
            Canvas { context, size in
                let width = size.width
                let height = size.height
                let midY = height / 2
                
                var path = Path()
                
                for x in stride(from: 0, to: width, by: 2) {
                    let relativeX = x / width
                    let amplitude = CGFloat(audioLevel) * height * 0.4
                    let frequency = 4.0
                    let y = midY + sin((relativeX * frequency * .pi * 2) + phase) * amplitude
                    
                    if x == 0 {
                        path.move(to: CGPoint(x: x, y: y))
                    } else {
                        path.addLine(to: CGPoint(x: x, y: y))
                    }
                }
                
                context.stroke(
                    path,
                    with: .color(waveColor),
                    lineWidth: 2
                )
            }
        }
        .onAppear {
            withAnimation(.linear(duration: 2).repeatForever(autoreverses: false)) {
                phase = .pi * 2
            }
        }
    }
    
    private var waveColor: Color {
        if audioLevel < 0.5 {
            return .green
        } else if audioLevel < 0.8 {
            return .yellow
        } else {
            return .red
        }
    }
}

struct TestRecordingPlayer: View {
    let url: URL
    @State private var isPlaying = false
    @State private var player: AVAudioPlayer?
    
    var body: some View {
        HStack {
            Button(action: togglePlayback) {
                HStack {
                    Image(systemName: isPlaying ? "pause.circle" : "play.circle")
                        .font(.title2)
                    Text(isPlaying ? "Pause" : "Play Test Recording")
                }
            }
            .buttonStyle(.bordered)
            
            if let player = player, isPlaying {
                Text(formatTime(player.currentTime))
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
        .onAppear {
            setupPlayer()
        }
        .onDisappear {
            player?.stop()
        }
    }
    
    private func setupPlayer() {
        do {
            player = try AVAudioPlayer(contentsOf: url)
            player?.prepareToPlay()
        } catch {
            print("Failed to setup player: \(error)")
        }
    }
    
    private func togglePlayback() {
        if isPlaying {
            player?.pause()
        } else {
            player?.play()
        }
        isPlaying.toggle()
    }
    
    private func formatTime(_ time: TimeInterval) -> String {
        let seconds = Int(time)
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

#Preview {
    AudioSettingsView()
        .frame(width: 600, height: 500)
}