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
    
    // Create a function to get a fresh RecordingSessionView instead of a stored property
    private func createRecordingSessionView() -> RecordingSessionView {
        return RecordingSessionView()
    }
    
    // Add a way to track the current state of the popup
    enum PopupState {
        case recording
        case transcribing
        case completed(String)
        case error(String)
        case noMicrophone
    }
    
    @Published var currentState: PopupState = .recording
    
    private init() {}
    
    var isWindowVisible: Bool {
        return popupWindow != nil && popupWindow!.isVisible
    }
    
    func togglePopupWindow() {
        let audioRecorder = AudioRecorder.shared
        
        // First check if we have any microphones available
        let availableMics = settingsManager.getAvailableMicrophones()
        if availableMics.isEmpty {
            // No microphones found - show error popup
            logger.log("No microphones found, showing error popup", level: .warning)
            showMicrophoneErrorPopup()
            return
        }
        
        // Check if we have microphone permission
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
                // Show the popup and start recording
                showPopupWindow()
                logger.log("Popup window toggled on", level: .info)
            }
        }
    }
    
    func showPopupWindow() {
        // If window already exists, close it first to ensure fresh state
        if let window = popupWindow {
            window.close()
            popupWindow = nil
            logger.log("Closed existing window before creating new one", level: .debug)
        }
        
        logger.log("Creating new recording session window", level: .info)
        
        // Get the height for the current state
        let height = currentState.windowHeight
        
        // Create a window without standard decorations and non-activating
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 160, height: height),
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
        
        // Reset state to recording
        currentState = .recording
        
        // Create a fresh view each time
        let freshView = createRecordingSessionView()
        let hostingView = NSHostingView(rootView: freshView)
        window.contentView = hostingView
        
        // Position window at top center of the screen
        positionWindowAtTopCenter(window)
        
        // Show window without activating app or making window key
        window.orderFront(nil)
        
        // Start audio recording and reset state
        audioRecorder.startRecording()
        
        // Keep a reference to the window
        self.popupWindow = window
        
        logger.log("New recording session window created and displayed", level: .debug)
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
        guard popupWindow != nil else { return }
        
        // Update state to show we're transcribing
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.currentState = .transcribing
            self.logger.log("Starting transcription process", level: .info)
            
            // Update the window size for the new state
            if let window = self.popupWindow {
                // Update window size
                let height = self.currentState.windowHeight
                window.setContentSize(NSSize(width: 160, height: height))
                
                // Force refresh the view with new state
                let freshView = self.createRecordingSessionView()
                let hostingView = NSHostingView(rootView: freshView)
                window.contentView = hostingView
                
                // Reposition to account for size change
                self.positionWindowAtTopCenter(window)
            }
        }
        
        // Stop recording first
        audioRecorder.stopRecording()
        
        // Stop audio level simulation
        stopAudioLevelSimulation()
        
        // Get the API key from settings
        let apiKey = settingsManager.getCurrentAPIKey()
        
        if apiKey.isEmpty {
            // Handle missing API key
            DispatchQueue.main.async { [weak self] in
                self?.currentState = .error("API key not set in settings")
                self?.logger.log("Cannot transcribe: API key not set", level: .error)
            }
            
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
                            
                            // Close window after pasting (with a small delay)
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                                self?.closePopupWindow()
                            }
                        }
                        
                        // Don't close window here - we'll do it after pasting
                        
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
            
            // Reset state to recording for next session
            currentState = .recording
            
            // Close the window
            window.close()
            popupWindow = nil
            logger.log("Recording session window closed", level: .debug)
        }
    }
    
    private func positionWindowAtTopCenter(_ window: NSWindow) {
        guard let screen = NSScreen.main else { return }
        
        let screenFrame = screen.visibleFrame
        
        // Make sure window size matches current state
        let height = currentState.windowHeight
        window.setContentSize(NSSize(width: 160, height: height))
        
        let windowSize = window.frame.size
        let centerX = screenFrame.midX - (windowSize.width / 2)
        let bottomY = screenFrame.minY + 20 // 20px from bottom
        
        let bottomCenterPoint = NSPoint(x: centerX, y: bottomY)
        window.setFrameOrigin(bottomCenterPoint)
        
        logger.log("Positioned window at: x=\(centerX), y=\(bottomY) with height: \(height)", level: .debug)
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
    
    // Add method to show error popup for no microphone
    private func showMicrophoneErrorPopup() {
        // If window already exists, just update its state
        if let window = popupWindow {
            logger.log("Updating existing popup window to show microphone error", level: .debug)
            currentState = .noMicrophone
            window.orderFront(nil)
            return
        }
        
        logger.log("Creating new window to show microphone error", level: .info)
        
        // Create a window without standard decorations and non-activating
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 240, height: 120),
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
        
        // Set up the window with the error view - use a fresh view
        currentState = .noMicrophone
        let freshView = createRecordingSessionView()
        let hostingView = NSHostingView(rootView: freshView)
        window.contentView = hostingView
        
        // Position window at top center of the screen
        positionWindowAtTopCenter(window)
        
        // Show window without activating app or making window key
        window.orderFront(nil)
        
        // Keep a reference to the window
        self.popupWindow = window
    }
}

// SwiftUI view for the recording session window
struct RecordingSessionView: View {
    @ObservedObject private var audioRecorder = AudioRecorder.shared
    @ObservedObject private var windowManager = PopupWindowManager.shared
    
    // Track local animation states
    @State private var isAnimationActive = false
    
    var body: some View {
        ZStack {
            Group {
                switch windowManager.currentState {
                case .recording:
                    VStack(spacing: 2) {
                        // Use the new VoiceAnimation instead of ParticleWaveEffect
                        VoiceAnimation(intensity: audioRecorder.audioLevel)
                            .frame(width: 150, height: 40)
                            .padding(.horizontal, 5)
                        
                        // Show recording time
                        if audioRecorder.isRecording {
                            Text(formatTime(audioRecorder.recordingTime))
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(.white.opacity(0.8))
                                .padding(.top, 4)
                        }
                    }
                    .padding(.horizontal, 5)
                    .padding(.vertical, 8)
                
                case .transcribing:
                    VStack(spacing: 5) {
                        // Existing TranscribingAnimation
                        TranscribingAnimation()
                            .frame(width: 150, height: 40)
                            .padding(.horizontal, 5)
                        
                        Text("Transcribing...")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.white)
                            .padding(.bottom, 5)
                    }
                    .padding(.horizontal, 5)
                    .padding(.vertical, 8)
                
                case .completed(let text):
                    // Success UI
                    Image(systemName: "checkmark.circle.fill")
                        .resizable()
                        .frame(width: 25, height: 25)
                        .foregroundColor(.green)
                        .padding()
                
                case .error(let message):
                    // Error UI - Show error text
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .resizable()
                            .frame(width: 16, height: 14)
                            .foregroundColor(.red)
                            .padding(.top, 2)
                        
                        Text("Error: \(message)")
                            .font(.system(size: 11))
                            .foregroundColor(.white)
                            .lineLimit(2)
                            .truncationMode(.tail)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .onHover { hovering in
                                if hovering {
                                    NSCursor.pointingHand.set()
                                } else {
                                    NSCursor.arrow.set()
                                }
                            }
                            .help(message)
                    }
                    .padding(10)
                    .frame(width: 160)
                
                case .noMicrophone:
                    // No microphone UI
                    VStack(spacing: 12) {
                        HStack {
                            Spacer()
                            Button(action: {
                                windowManager.closePopupWindow()
                            }) {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 14))
                                    .foregroundColor(.white.opacity(0.7))
                                    .padding(4)
                            }
                            .buttonStyle(PlainButtonStyle())
                            .contentShape(Rectangle())
                        }
                        .padding(.top, 4)
                        .padding(.trailing, 4)
                        
                        Spacer()
                        
                        Image(systemName: "mic.slash.fill")
                            .resizable()
                            .frame(width: 32, height: 32)
                            .foregroundColor(.red)
                        
                        Text("No Microphones Found")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.white)
                        
                        Button(action: {
                            windowManager.closePopupWindow()
                            NSApp.sendAction(#selector(AppDelegate.openSettings), to: nil, from: nil)
                        }) {
                            Text("Open Settings")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.black)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Color.white)
                                .cornerRadius(12)
                        }
                        .buttonStyle(PlainButtonStyle())
                        
                        Spacer()
                    }
                    .frame(width: 240, height: 120)
                }
            }
            .frame(maxWidth: .infinity)
            .background(Color.black.opacity(0.6))
            .cornerRadius(16)
            .shadow(color: .black.opacity(0.2), radius: 5)
            
            // Close button - positioned in the top-right corner
            // Only show when not in transcribing state
            if case .transcribing = windowManager.currentState {
                // Don't show close button during transcription
            } else {
                VStack {
                    HStack {
                        Spacer()
                        Button(action: {
                            windowManager.closePopupWindow()
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 14))
                                .foregroundColor(.white.opacity(0.7))
                                .padding(4)
                        }
                        .buttonStyle(PlainButtonStyle())
                        .contentShape(Rectangle())
                    }
                    Spacer()
                }
                .padding(4)
            }
        }
        .frame(width: 160, height: windowManager.currentState.windowHeight)
        .onAppear {
            isAnimationActive = true
        }
        .onDisappear {
            isAnimationActive = false
        }
    }
    
    private func formatTime(_ timeInterval: TimeInterval) -> String {
        let minutes = Int(timeInterval) / 60
        let seconds = Int(timeInterval) % 60
        let milliseconds = Int((timeInterval.truncatingRemainder(dividingBy: 1)) * 100)
        return String(format: "%02d:%02d.%02d", minutes, seconds, milliseconds)
    }
}

// Extension to check if the state is an error state and get appropriate height
extension PopupWindowManager.PopupState {
    var isError: Bool {
        if case .error(_) = self {
            return true
        }
        return false
    }
    
    var windowHeight: CGFloat {
        switch self {
        case .error:
            return 120
        case .recording, .transcribing, .completed:
            return 60
        case .noMicrophone:
            return 120
        }
    }
}
