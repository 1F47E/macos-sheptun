import Cocoa
import SwiftUI

class PopupWindowManager: ObservableObject {
    static let shared = PopupWindowManager()
    
    private var popupWindow: NSWindow?
    private let logger = Logger.shared
    private let audioRecorder = AudioRecorder.shared
    private let openAIManager = OpenAIManager.shared
    private let settingsManager = SettingsManager.shared
    private var audioLevelSimulationTimer: Timer?
    
    // Add a way to track the current state of the popup
    enum PopupState {
        case recording
        case transcribing
        case completed(String)
        case error(String)
    }
    
    @Published var currentState: PopupState = .recording
    
    private init() {}
    
    var isWindowVisible: Bool {
        return popupWindow != nil && popupWindow!.isVisible
    }
    
    func togglePopupWindow() {
        if isWindowVisible {
            // If already visible, start transcription process
            startTranscription()
        } else {
            // If not visible, show the popup and start recording
            showPopupWindow()
            logger.log("Popup window toggled on", level: .info)
        }
    }
    
    func showPopupWindow() {
        // If window already exists, just show it
        if let window = popupWindow {
            logger.log("Reusing existing popup window", level: .debug)
            positionWindowAtTopCenter(window)
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            
            // Reset state to recording
            currentState = .recording
            return
        }
        
        logger.log("Creating new recording session window", level: .info)
        
        // Create a window without standard decorations
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 180),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        
        // Configure window appearance
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = true
        window.level = .floating
        window.isReleasedWhenClosed = false
        
        // Set up the window to be frameless and visually appealing
        let hostingView = NSHostingView(rootView: RecordingSessionView())
        window.contentView = hostingView
        
        // Position window at top center of the screen
        positionWindowAtTopCenter(window)
        
        // Show window and start recording
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        
        // Start audio recording and reset state
        currentState = .recording
        audioRecorder.startRecording()
        
        // Only fall back to simulation if real audio monitoring fails
        // We'll wait a bit to see if real monitoring is working
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            if self?.audioRecorder.audioLevel ?? 0 <= 0.01 {
                self?.startAudioLevelSimulation()
                self?.logger.log("Falling back to audio level simulation", level: .warning)
            } else {
                self?.logger.log("Using real audio levels from microphone", level: .info)
            }
        }
        
        // Keep a reference to the window
        self.popupWindow = window
    }
    
    func startTranscription() {
        guard let window = popupWindow else { return }
        
        // Update state to show we're transcribing
        currentState = .transcribing
        logger.log("Starting transcription process", level: .info)
        
        // Stop recording first
        audioRecorder.stopRecording()
        
        // Stop audio level simulation
        stopAudioLevelSimulation()
        
        // Get the API key from settings
        let apiKey = settingsManager.openAIKey
        
        if apiKey.isEmpty {
            // Handle missing API key
            currentState = .error("API key not set in settings")
            logger.log("Cannot transcribe: API key not set", level: .error)
            
            // Close the window after a delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
                self?.closePopupWindow()
            }
            return
        }
        
        // Start transcription in a background task
        Task { [weak self] in
            guard let self = self else { return }
            
            do {
                // Get the latest audio buffer - this is critical!
                guard let audioData = audioRecorder.getLatestAudioBuffer() else {
                    await MainActor.run {
                        currentState = .error("No audio data available")
                        logger.log("No audio data available for transcription", level: .error)
                    }
                    
                    // Close window after a delay
                    await MainActor.run {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
                            self?.closePopupWindow()
                        }
                    }
                    return
                }
                
                logger.log("Got audio buffer with size: \(audioData.count) bytes", level: .debug)
                
                // Create a temporary WAV file from the audio data
                let tempDir = NSTemporaryDirectory()
                let tempFilename = "recording_\(Int(Date().timeIntervalSince1970)).wav"
                let tempURL = URL(fileURLWithPath: tempDir).appendingPathComponent(tempFilename)
                
                // Use the audio format from the audio recorder
                if let audioFormat = audioRecorder.audioFormat {
                    logger.log("Creating WAV file with format: \(audioFormat.description)", level: .debug)
                    
                    // Use OpenAIManager to create WAV data from the PCM buffer
                    if let wavData = openAIManager.createWavData(fromPCMData: audioData, format: audioFormat) {
                        try wavData.write(to: tempURL)
                        logger.log("Created WAV file with size: \(wavData.count) bytes", level: .debug)
                    } else {
                        logger.log("Failed to create WAV file, writing raw data", level: .warning)
                        try audioData.write(to: tempURL)
                    }
                } else {
                    logger.log("No audio format available, writing raw data", level: .warning)
                    try audioData.write(to: tempURL)
                }
                
                // Attempt to transcribe the audio with the WAV file we just created
                let result = await openAIManager.transcribeAudioFile(
                    audioFileURL: tempURL,
                    apiKey: apiKey,
                    model: .gpt4oMiniTranscribe
                )
                
                // Handle the result on the main thread
                await MainActor.run {
                    switch result {
                    case .success(let transcription):
                        // Transcription successful
                        logger.log("Transcription successful: \(transcription)", level: .info)
                        currentState = .completed(transcription)
                        
                        // Copy to clipboard
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(transcription, forType: .string)
                        
                        // Close window after a short delay
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                            self?.closePopupWindow()
                        }
                        
                    case .failure(let error):
                        // Transcription failed
                        logger.log("Transcription failed: \(error.localizedDescription)", level: .error)
                        currentState = .error(error.localizedDescription)
                        
                        // Close window after a delay
                        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
                            self?.closePopupWindow()
                        }
                    }
                }
            } catch {
                await MainActor.run {
                    logger.log("Failed to process audio: \(error.localizedDescription)", level: .error)
                    currentState = .error("Failed to process audio: \(error.localizedDescription)")
                    
                    // Close window after a delay
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
                        self?.closePopupWindow()
                    }
                }
            }
        }
    }
    
    func closePopupWindow() {
        if let window = popupWindow {
            // Stop audio recording
            audioRecorder.stopRecording()
            
            // Stop audio level simulation
            stopAudioLevelSimulation()
            
            // Close the window
            window.close()
            popupWindow = nil
            logger.log("Recording session window closed", level: .debug)
        }
    }
    
    private func positionWindowAtTopCenter(_ window: NSWindow) {
        guard let screen = NSScreen.main else { return }
        
        let screenFrame = screen.visibleFrame
        let windowSize = window.frame.size
        
        let centerX = screenFrame.midX - (windowSize.width / 2)
        let topY = screenFrame.maxY - windowSize.height - 20 // 20px from top
        
        let topCenterPoint = NSPoint(x: centerX, y: topY)
        window.setFrameTopLeftPoint(topCenterPoint)
        
        logger.log("Positioned window at: x=\(centerX), y=\(topY)", level: .debug)
    }
    
    private func startAudioLevelSimulation() {
        // Create a timer to simulate audio level changes
        audioLevelSimulationTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.audioRecorder.simulateAudioLevels()
        }
    }
    
    private func stopAudioLevelSimulation() {
        audioLevelSimulationTimer?.invalidate()
        audioLevelSimulationTimer = nil
    }
}

// SwiftUI view for the recording session window
struct RecordingSessionView: View {
    @ObservedObject private var audioRecorder = AudioRecorder.shared
    @ObservedObject private var windowManager = PopupWindowManager.shared
    
    var body: some View {
        VStack(spacing: 12) {
            Text(titleForState)
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(.white)
            
            Group {
                switch windowManager.currentState {
                case .recording:
                    // Recording UI
                    // Debug volume level
                    Text("Volume: \(String(format: "%.2f", audioRecorder.audioLevel))")
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundColor(.gray)
                    
                    // Timer display
                    Text(formatTime(audioRecorder.recordingTime))
                        .font(.system(size: 24, weight: .medium, design: .monospaced))
                        .foregroundColor(.white)
                    
                    // Audio visualization with flowing dots
                    ParticleWaveEffect(intensity: audioRecorder.audioLevel)
                        .height(50)
                        .baseColor(.blue)
                        .accentColor(.purple)
                        .padding(.horizontal)
                    
                    Text("Speak now...")
                        .font(.system(size: 14))
                        .foregroundColor(.gray)
                
                case .transcribing:
                    // Transcribing UI
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(1.5)
                        .padding()
                    
                    Text("Transcribing audio...")
                        .font(.system(size: 16))
                        .foregroundColor(.white)
                
                case .completed(let text):
                    // Success UI
                    Image(systemName: "checkmark.circle.fill")
                        .resizable()
                        .frame(width: 40, height: 40)
                        .foregroundColor(.green)
                        .padding()
                    
                    Text(text)
                        .font(.system(size: 14))
                        .foregroundColor(.white)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                    
                    Text("Copied to clipboard")
                        .font(.system(size: 12))
                        .foregroundColor(.gray)
                
                case .error(let message):
                    // Error UI
                    Image(systemName: "exclamationmark.triangle.fill")
                        .resizable()
                        .frame(width: 40, height: 35)
                        .foregroundColor(.red)
                        .padding()
                    
                    Text("Error: \(message)")
                        .font(.system(size: 14))
                        .foregroundColor(.white)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
            }
            .padding(.bottom, 5)
        }
        .frame(width: 400, height: 200)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(red: 0.1, green: 0.1, blue: 0.1, opacity: 0.95))
        )
        .shadow(color: Color.black.opacity(0.4), radius: 10, x: 0, y: 5)
    }
    
    private var titleForState: String {
        switch windowManager.currentState {
        case .recording:
            return "Recording Session"
        case .transcribing:
            return "Processing Audio"
        case .completed:
            return "Transcription Complete"
        case .error:
            return "Transcription Error"
        }
    }
    
    private func formatTime(_ timeInterval: TimeInterval) -> String {
        let minutes = Int(timeInterval) / 60
        let seconds = Int(timeInterval) % 60
        let milliseconds = Int((timeInterval.truncatingRemainder(dividingBy: 1)) * 100)
        return String(format: "%02d:%02d.%02d", minutes, seconds, milliseconds)
    }
}

// Animated wave background for the audio visualization
struct WaveShape: Shape {
    var audioLevel: Float
    var phase: Double
    
    // For Shape animation
    var animatableData: AnimatablePair<Float, Double> {
        get { AnimatablePair(audioLevel, phase) }
        set {
            audioLevel = newValue.first
            phase = newValue.second
        }
    }
    
    func path(in rect: CGRect) -> Path {
        let width = rect.width
        let height = rect.height
        let midHeight = height / 2
        
        // Higher amplitude when audio level is higher
        let amplitude = CGFloat(audioLevel) * height * 0.4
        
        // Number of waves to display
        let waves = 3
        
        var path = Path()
        path.move(to: CGPoint(x: 0, y: midHeight))
        
        for x in stride(from: 0, to: width, by: 1) {
            let relativeX = x / width
            
            // Multiple sine waves with different frequencies
            let sin1 = sin(relativeX * .pi * 2 * Double(waves) + phase)
            let sin2 = sin(relativeX * .pi * 4 * Double(waves) + phase * 1.5) * 0.5
            
            // Combine waves
            let combinedSin = (sin1 + sin2) / 1.5
            
            let y = midHeight + CGFloat(combinedSin) * amplitude
            path.addLine(to: CGPoint(x: x, y: y))
        }
        
        return path
    }
} 