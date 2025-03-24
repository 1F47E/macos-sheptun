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
        let audioRecorder = AudioRecorder.shared
        
        // First check if we have microphone permission
        if !audioRecorder.checkMicrophonePermission() {
            logger.log("Microphone permission not granted, requesting access", level: .warning)
            
            // Request microphone permission
            audioRecorder.requestMicrophonePermission { [weak self] granted in
                guard let self = self else { return }
                
                if granted {
                    self.logger.log("Microphone access granted, showing popup", level: .info)
                    // Now that we have permission, show the popup
                    self.showPopupWindowAfterPermissionCheck()
                } else {
                    self.logger.log("Microphone access not granted, cannot record", level: .warning)
                }
            }
        } else {
            // We have permission, proceed normally
            if isWindowVisible {
                // If already visible, start transcription process
                startTranscription()
            } else {
                // If not visible, show the popup and start recording
                showPopupWindow()
                logger.log("Popup window toggled on", level: .info)
            }
        }
    }
    
    func showPopupWindow() {
        // If window already exists, just show it
        if let window = popupWindow {
            logger.log("Reusing existing popup window", level: .debug)
            positionWindowAtTopCenter(window)
            window.orderFront(nil)
            
            // Reset state to recording
            currentState = .recording
            return
        }
        
        logger.log("Creating new recording session window", level: .info)
        
        // Create a window without standard decorations and non-activating
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 80),
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
        
        // Show window without activating app or making window key
        window.orderFront(nil)
        
        // Start audio recording and reset state
        currentState = .recording
        audioRecorder.startRecording()
        
        // Keep a reference to the window
        self.popupWindow = window
    }
    
    // New method to handle showing popup after permission check
    private func showPopupWindowAfterPermissionCheck() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            if !self.isWindowVisible {
                self.showPopupWindow()
                self.logger.log("Popup window shown after permission granted", level: .info)
            }
        }
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
        let apiKey = settingsManager.getCurrentAPIKey()
        
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
                // Get the path to the recorded file directly from the AudioRecorder
                guard let recordedFileURL = audioRecorder.getRecordingFileURL() else {
                    await MainActor.run {
                        self.currentState = .error("Recording file not found")
                        self.logger.log("No recording file available for transcription", level: .error)
                    }
                    
                    // Close window after a delay
                    await MainActor.run {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
                            self?.closePopupWindow()
                        }
                    }
                    return
                }
                
                self.logger.log("Using recorded audio file at: \(recordedFileURL.path)", level: .debug)
                
                // Get file size for debugging
                do {
                    let attributes = try FileManager.default.attributesOfItem(atPath: recordedFileURL.path)
                    if let fileSize = attributes[.size] as? NSNumber {
                        self.logger.log("Audio file size for transcription: \(fileSize.intValue) bytes", level: .debug)
                    }
                } catch {
                    self.logger.log("Error getting file size: \(error.localizedDescription)", level: .warning)
                }
                
                // Get the current AI provider based on settings
                let currentProvider = settingsManager.getCurrentAIProvider()
                let apiProvider = AIProviderFactory.getProvider(type: currentProvider)
                
                // Attempt to transcribe the audio with the recorded file
                let result = await apiProvider.transcribeAudio(
                    audioFileURL: recordedFileURL,
                    apiKey: apiKey,
                    model: settingsManager.transcriptionModel,
                    temperature: settingsManager.transcriptionTemperature,
                    language: "en"
                )
                
                // Handle the result on the main thread
                await MainActor.run {
                    switch result {
                    case .success(let transcription):
                        // Transcription successful
                        self.logger.log("Transcription successful: \(transcription)", level: .info)
                        
                        // Copy to clipboard
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(transcription, forType: .string)
                        
                        // Simulate Cmd+V paste keystroke
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                            let source = CGEventSource(stateID: .hidSystemState)
                            
                            // Create a 'v' key down event with command modifier
                            let cmdV = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true)
                            cmdV?.flags = .maskCommand
                            
                            // Post the event
                            cmdV?.post(tap: .cghidEventTap)
                            
                            // Create a 'v' key up event
                            let cmdVUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false)
                            cmdVUp?.flags = .maskCommand
                            cmdVUp?.post(tap: .cghidEventTap)
                        }
                        
                        // Close window immediately
                        self.closePopupWindow()
                        
                    case .failure(let error):
                        // Transcription failed
                        self.logger.log("Transcription failed: \(error.localizedDescription)", level: .error)
                        self.currentState = .error(error.localizedDescription)
                        
                        // Close window after a delay
                        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
                            self?.closePopupWindow()
                        }
                    }
                }
            } catch {
                await MainActor.run {
                    self.logger.log("Failed to process audio: \(error.localizedDescription)", level: .error)
                    self.currentState = .error("Failed to process audio: \(error.localizedDescription)")
                    
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
        let bottomY = screenFrame.minY + 20 // 20px from bottom
        
        let bottomCenterPoint = NSPoint(x: centerX, y: bottomY)
        window.setFrameOrigin(bottomCenterPoint)
        
        logger.log("Positioned window at: x=\(centerX), y=\(bottomY)", level: .debug)
    }
    
    // Audio level simulation methods
    private func startAudioLevelSimulation() {
        stopAudioLevelSimulation()
        
        audioLevelSimulationTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            // Simulate a "breathing" audio level between 0.1 and 0.7
            let time = Date().timeIntervalSince1970
            let level = (sin(time * 3) + 1) / 2 * 0.6 + 0.1
            
            DispatchQueue.main.async {
                self?.audioRecorder.audioLevel = Float(level)
            }
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
        VStack(spacing: 10) {
            Group {
                switch windowManager.currentState {
                case .recording:
                    // Recording UI - Minimalistic
                    ParticleWaveEffect(intensity: audioRecorder.audioLevel)
                        .height(40)
                        .baseColor(.blue)
                        .accentColor(.purple)
                        .padding(.horizontal)
                
                case .transcribing:
                    // Transcribing UI
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(1.2)
                        .padding()
                
                case .completed(let text):
                    // Success UI
                    Image(systemName: "checkmark.circle.fill")
                        .resizable()
                        .frame(width: 30, height: 30)
                        .foregroundColor(.green)
                        .padding()
                
                case .error(let message):
                    // Error UI - Show error text
                    VStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .resizable()
                            .frame(width: 25, height: 22)
                            .foregroundColor(.red)
                            .padding(.top, 8)
                        
                        Text("Error: \(message)")
                            .font(.system(size: 12))
                            .foregroundColor(.white)
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                    .frame(width: 200, height: 120)
                }
            }
        }
        .frame(width: 200, height: windowManager.currentState.isError ? 120 : 80)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(red: 0.1, green: 0.1, blue: 0.1, opacity: 0.85))
        )
        .shadow(color: Color.black.opacity(0.3), radius: 6, x: 0, y: 2)
    }
    
    private func formatTime(_ timeInterval: TimeInterval) -> String {
        let minutes = Int(timeInterval) / 60
        let seconds = Int(timeInterval) % 60
        let milliseconds = Int((timeInterval.truncatingRemainder(dividingBy: 1)) * 100)
        return String(format: "%02d:%02d.%02d", minutes, seconds, milliseconds)
    }
}

// Extension to check if the state is an error state
extension PopupWindowManager.PopupState {
    var isError: Bool {
        if case .error(_) = self {
            return true
        }
        return false
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