import SwiftUI
import AVFoundation

struct AudioSettingsView: View {
    @StateObject private var settings = SettingsManager.shared
    @State private var availableMicrophones: [SettingsManager.MicrophoneDevice] = []
    @State private var audioLevel: Float = 0
    @State private var audioMonitor: AudioLevelMonitor? = nil
    @State private var audioMonitorError: String? = nil
    @State private var isRefreshing: Bool = false
    
    private let logger = Logger.shared
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                microphoneSelectionSection
                
                audioLevelSection
                
                audioQualitySection
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
                        HStack {
                            Image(systemName: "mic")
                                .font(.body)
                                .foregroundColor(.secondary)
                            
                            Picker("", selection: $settings.selectedMicrophoneID) {
                                ForEach(availableMicrophones) { mic in
                                    Text(mic.name)
                                        .tag(mic.id)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(MenuPickerStyle())
                            .onChange(of: settings.selectedMicrophoneID) { _, newValue in
                                settings.saveSettings()
                                startAudioMonitoring(deviceID: newValue)
                                logger.log("Selected microphone changed to: \(newValue)", level: .info)
                            }
                            
                            Spacer()
                            
                            Button(action: refreshMicrophones) {
                                Image(systemName: "arrow.clockwise")
                                    .font(.system(size: 14))
                                    .rotationEffect(.degrees(isRefreshing ? 360 : 0))
                                    .animation(isRefreshing ? .linear(duration: 1).repeatForever(autoreverses: false) : .default, value: isRefreshing)
                            }
                            .buttonStyle(PlainButtonStyle())
                            .help("Refresh microphone list")
                            .disabled(isRefreshing)
                        }
                        .padding()
                        
                        if let selectedMic = availableMicrophones.first(where: { $0.id == settings.selectedMicrophoneID }) {
                            HStack {
                                Text("Device ID: \(selectedMic.id)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Spacer()
                            }
                            .padding(.horizontal)
                            .padding(.bottom, 8)
                        }
                    }
                }
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
                        Text("16 kHz")
                            .font(.system(.body, design: .monospaced))
                    }
                    
                    Divider()
                    
                    HStack {
                        Label("Format", systemImage: "doc.badge.waveform")
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("M4A (AAC 32kbps)")
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
    
    private var levelColor: Color {
        if audioLevel < 0.5 {
            return .green
        } else if audioLevel < 0.8 {
            return .yellow
        } else {
            return .red
        }
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
    
    private func refreshMicrophones() {
        logger.log("Refreshing microphone list", level: .info)
        isRefreshing = true
        
        // Add a small delay to show the animation
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            let newMicrophones = settings.getAvailableMicrophones()
            availableMicrophones = newMicrophones
            logger.log("Refreshed microphone list: found \(newMicrophones.count) devices", level: .info)
            
            // Check if the currently selected microphone is still available
            if !newMicrophones.contains(where: { $0.id == settings.selectedMicrophoneID }) {
                // Current microphone is no longer available, select first available or empty
                if let firstMic = newMicrophones.first {
                    settings.selectedMicrophoneID = firstMic.id
                    settings.saveSettings()
                    startAudioMonitoring(deviceID: firstMic.id)
                    logger.log("Previous microphone unavailable, switched to: \(firstMic.name)", level: .warning)
                } else {
                    settings.selectedMicrophoneID = ""
                    settings.saveSettings()
                    stopAudioMonitoring()
                    logger.log("No microphones available after refresh", level: .warning)
                }
            }
            
            isRefreshing = false
        }
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

#Preview {
    AudioSettingsView()
        .frame(width: 600, height: 500)
}