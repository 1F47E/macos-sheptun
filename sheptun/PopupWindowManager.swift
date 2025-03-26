//
//  PopupWindowManager.swift
//  sheptun
//
//  Created by Example on 2025-03-26.
//

import Cocoa
import SwiftUI

/// Represents the various states of our floating popup
enum TranscriberState {
    case recording
    case transcribing
    case completed(String)
    case error(String)
    case noMicrophone
}

/// Manages a single, reusable NSWindow that shows a SwiftUI content view.
/// The view reacts to `currentState` changes rather than creating new windows.
class PopupWindowManager: NSObject, ObservableObject {
    
    static let shared = PopupWindowManager()
    
    private let logger = Logger.shared
    private let audioRecorder = AudioRecorder.shared
    private let settingsManager = SettingsManager.shared
    
    /// The current state of the transcriber window (recording, error, etc).
    @Published var currentState: TranscriberState = .recording {
        didSet {
            // Whenever state changes, update the SwiftUI content and possibly the window size.
            updateWindowSizeIfNeeded()
        }
    }
    
    /// The floating NSWindow we create once and reuse.
    private var popupWindow: NSWindow?
    
    /// A single hosting controller that displays the SwiftUI content.
    /// We update its rootView whenever `currentState` changes.
    private var hostingController: NSHostingController<TranscriberPopupView>?
    
    /// We'll set up a timer for simulating or tracking audio levels if needed.
    private var audioLevelSimulationTimer: Timer?
    
    // MARK: - Showing / Hiding
    
    /// Toggles between recording and transcribing states.
    /// If no window is visible, starts recording.
    /// If recording is in progress, stops recording and starts transcription.
    func toggleRecording() {
        if popupWindow?.isVisible == true {
            // Check current state with pattern matching
            switch currentState {
            case .recording:
                // Already recording, start transcription
                startTranscription()
            default:
                // For other states like error or transcribing, just close
                closePopup()
            }
        } else {
            // Not recording, start new recording
            showOrRecord()
        }
    }
    
    /// Shows the popup near the mouse pointer (top-left corner pinned),
    /// and sets up for recording. If no mic or permission, transitions to error states.
    func showOrRecord() {
        // Check mic presence
        let availableMics = settingsManager.getAvailableMicrophones()
        if availableMics.isEmpty {
            logger.log("No microphones found => show noMicrophone error", level: .warning)
            currentState = .noMicrophone
            showWindowAtMousePointer()
            return
        }
        
        // Check mic permission
        if !audioRecorder.checkMicrophonePermission() {
            logger.log("Mic permission not granted => requesting...", level: .warning)
            audioRecorder.requestMicrophonePermission { [weak self] granted in
                guard let self = self else { return }
                if granted {
                    self.logger.log("Mic permission granted => show window & record", level: .info)
                    DispatchQueue.main.async {
                        self.currentState = .recording
                        self.showWindowAtMousePointer()
                        self.audioRecorder.startRecording()
                    }
                } else {
                    self.logger.log("Mic permission denied => error state", level: .warning)
                    DispatchQueue.main.async {
                        self.currentState = .error("Microphone access denied.")
                        self.showWindowAtMousePointer()
                    }
                }
            }
        } else {
            // We have a microphone and permission => show & record
            currentState = .recording
            showWindowAtMousePointer()
            audioRecorder.startRecording()
        }
    }
    
    /// Closes (hides) the popup window.
    func closePopup() {
        audioRecorder.stopRecording()
        stopAudioLevelSimulation()
        popupWindow?.orderOut(nil)
    }
    
    // MARK: - Transcription
    
    /// User triggers transcription after recording.
    func startTranscription() {
        guard popupWindow?.isVisible == true else { return }
        
        currentState = .transcribing
        audioRecorder.stopRecording()
        stopAudioLevelSimulation()
        
        let apiKey = settingsManager.getCurrentAPIKey()
        if apiKey.isEmpty {
            currentState = .error("API Key not set in settings.")
            return
        }
        
        // In your code: transcribe in background
        Task.detached { [weak self] in
            guard let self = self else { return }
            
            guard let recordedFileURL = self.audioRecorder.getRecordingFileURL() else {
                await MainActor.run {
                    self.currentState = .error("Recording file not found.")
                }
                return
            }
            
            let providerType = self.settingsManager.getCurrentAIProvider()
            let provider = AIProviderFactory.getProvider(type: providerType)
            
            let result = await provider.transcribeAudio(
                audioFileURL: recordedFileURL,
                apiKey: apiKey,
                model: self.settingsManager.transcriptionModel,
                temperature: self.settingsManager.transcriptionTemperature,
                language: "en"
            )
            
            await MainActor.run {
                switch result {
                case .success(let transcription):
                    // Copy result to clipboard, simulate Cmd+V, etc.
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(transcription, forType: .string)
                    self.simulatePasteAndClose()
                    
                case .failure(let error):
                    self.currentState = .error("Transcription failed: \(error.localizedDescription)")
                }
            }
        }
    }
    
    private func simulatePasteAndClose() {
        // 1) Close the popup immediately
        closePopup()
        
        // 2) Then post Cmd+V after 0.2s so the previously used app has focus
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            guard let source = CGEventSource(stateID: .combinedSessionState) else { return }
            
            let cmdVDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true)
            cmdVDown?.flags = .maskCommand
            
            let cmdVUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false)
            cmdVUp?.flags = .maskCommand
            
            cmdVDown?.post(tap: .cgSessionEventTap)
            cmdVUp?.post(tap: .cgSessionEventTap)
        }
    }
    
    // MARK: - Window Creation & Positioning
    
    /// Creates the NSWindow if needed, updates the SwiftUI content, and
    /// positions it at the mouse pointer (pinned top-left). Clamped to screen bounds.
    private func showWindowAtMousePointer() {
        // Create the window once
        if popupWindow == nil {
            createPopupWindow()
        }
        guard let window = popupWindow, let controller = hostingController else { return }
        
        // Update SwiftUI content to reflect new state
        controller.rootView = TranscriberPopupView(manager: self)
        
        // Resize the window for the current state (keep top-left corner the same)
        updateWindowSizeIfNeeded()
        
        // Place top-left near mouse pointer
        positionTopLeftAtMouse(for: window)
        
        // Show the window in front
        window.orderFront(nil)
    }
    
    /// Actually creates the floating NSWindow and the hosting controller (once).
    private func createPopupWindow() {
        // Decide an initial size (e.g. for 'recording')
        let size = currentState.windowSize
        
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = true
        
        // Create SwiftUI hosting
        let rootView = TranscriberPopupView(manager: self)
        let controller = NSHostingController(rootView: rootView)
        
        window.contentView = controller.view
        self.popupWindow = window
        self.hostingController = controller
        
        logger.log("Created a single reusable window & hosting controller", level: .info)
    }
    
    /// Re-sizes the window if the needed height changed (width is fixed).
    /// This keeps the top-left corner pinned, so it expands downward.
    private func updateWindowSizeIfNeeded() {
        guard let window = popupWindow else { return }
        
        // Current frame
        let oldFrame = window.frame
        let neededSize = currentState.windowSize
        
        // If the width or height differ, update. Keep the same `origin.y` for top-left pin.
        let deltaHeight = neededSize.height - oldFrame.size.height
        
        if abs(deltaHeight) > 0.1 || abs(neededSize.width - oldFrame.size.width) > 0.1 {
            // Keep top-left corner the same
            let newOrigin = NSPoint(x: oldFrame.origin.x,
                                    y: oldFrame.origin.y - deltaHeight)
            
            let newFrame = NSRect(origin: newOrigin, size: neededSize)
            window.setFrame(newFrame, display: true, animate: true)
        }
    }
    
    /// Positions the **top-left** of the window near the mouse pointer,
    /// clamped so it doesn't go off-screen.
    private func positionTopLeftAtMouse(for window: NSWindow) {
        let mouseLoc = NSEvent.mouseLocation  // In global screen coords
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(mouseLoc) })
               ?? NSScreen.main else { return }
        
        let windowSize = currentState.windowSize
        let screenFrame = screen.visibleFrame
        
        // The top-left corner we want
        let desiredOriginX = mouseLoc.x
        let desiredOriginY = mouseLoc.y
        
        // Now clamp so the entire window stays on this screen
        let minX = screenFrame.minX
        let maxX = screenFrame.maxX - windowSize.width
        let minY = screenFrame.minY
        let maxY = screenFrame.maxY
        
        // We want top-left pinned, so the actual "origin" in NSWindow coords is:
        // (x, y - height). We'll clamp that in two steps:
        
        var clampedX = min(maxX, desiredOriginX)
        clampedX = max(minX, clampedX)
        
        // top-left is desiredOriginY; the window origin is bottom-left
        var topLeftY = desiredOriginY
        var bottomY = topLeftY - windowSize.height
        
        // clamp the bottom
        if bottomY < minY {
            bottomY = minY
            topLeftY = bottomY + windowSize.height
        }
        // clamp the top
        if topLeftY > maxY {
            topLeftY = maxY
            bottomY = topLeftY - windowSize.height
        }
        
        let finalOrigin = NSPoint(x: clampedX, y: bottomY)
        window.setFrameOrigin(finalOrigin)
    }
    
    // MARK: - Audio Level Simulation / Cleanup
    
    func startAudioLevelSimulation() {
        stopAudioLevelSimulation()
        audioLevelSimulationTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            let t = Date().timeIntervalSince1970
            let level = (sin(t * 3) + 1) / 2 * 0.6 + 0.1
            DispatchQueue.main.async {
                self.audioRecorder.audioLevel = Float(level)
            }
        }
    }
    
    func stopAudioLevelSimulation() {
        audioLevelSimulationTimer?.invalidate()
        audioLevelSimulationTimer = nil
    }
}

// MARK: - SwiftUI Content

/// The SwiftUI view that displays inside our single NSWindow.
/// Observes the `PopupWindowManager` to show different states.
/// References the separate `VoiceAnimation` in `VoiceAnimation.swift`.
struct TranscriberPopupView: View {
    
    @ObservedObject var manager: PopupWindowManager
    @ObservedObject var audioRecorder = AudioRecorder.shared
    
    var body: some View {
        ZStack {
            // Main content with corner radius background
            content
                .frame(width: manager.currentState.windowSize.width,
                       height: manager.currentState.windowSize.height)
                .background(Color.black.opacity(0.6))
                .cornerRadius(12)
                .shadow(radius: 4)
            
            // Close button for all states except `transcribing`
            if case .transcribing = manager.currentState {
                // Hide close button
            } else if case .noMicrophone = manager.currentState {
                // noMicrophone view has its own close button
            } else {
                closeButton
            }
        }
    }
    
    @ViewBuilder
    private var content: some View {
        switch manager.currentState {
        case .recording:
            // Show wave lines from VoiceAnimation.swift
            VoiceAnimation(intensity: audioRecorder.audioLevel)
                .frame(width: 150, height: 40)
            
        case .transcribing:
            // Simple spinner
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                .scaleEffect(0.8)
            
        case .completed:
            // Checkmark
            Image(systemName: "checkmark.circle.fill")
                .resizable()
                .frame(width: 28, height: 28)
                .foregroundColor(.green)
            
        case .error(let message):
            // Expand width, multiline, selectable
            VStack(spacing: 8) {
                HStack(alignment: .top) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.red)
                        .padding(.top, 2)
                    Text(message)
                        .foregroundColor(.white)
                        .font(.system(size: 12))
                        .textSelection(.enabled)
                }
            }
            .padding()
            
        case .noMicrophone:
            // Larger, custom layout with built-in close
            noMicrophoneView
        }
    }
    
    private var noMicrophoneView: some View {
        VStack(spacing: 10) {
            HStack {
                Spacer()
                Button(action: {
                    manager.closePopup()
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.white.opacity(0.7))
                }
                .buttonStyle(PlainButtonStyle())
            }
            Spacer()
            
            Image(systemName: "mic.slash.fill")
                .resizable()
                .frame(width: 32, height: 32)
                .foregroundColor(.red)
            
            Text("No Microphones Found")
                .foregroundColor(.white)
            
            Button(action: {
                manager.closePopup()
                // e.g. open app settings
                NSApp.sendAction(#selector(AppDelegate.openSettings), to: nil, from: nil)
            }) {
                Text("Open Settings")
                    .foregroundColor(.black)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.white)
                    .cornerRadius(8)
            }
            Spacer()
        }
        .frame(width: manager.currentState.windowSize.width,
               height: manager.currentState.windowSize.height)
        .padding()
    }
    
    /// A small close button pinned top-right
    private var closeButton: some View {
        VStack {
            HStack {
                Spacer()
                Button(action: {
                    manager.closePopup()
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.white.opacity(0.7))
                }
                .buttonStyle(PlainButtonStyle())
                .padding(6)
            }
            Spacer()
        }
    }
}

// MARK: - Calculating Window Size

extension TranscriberState {
    /// We define a fixed width (240 for errors & noMicrophone, 160 for normal),
    /// and heights that fit each state. Adjust as needed.
    var windowSize: NSSize {
        switch self {
        case .recording, .transcribing, .completed:
            return NSSize(width: 160, height: 60)
        case .error:
            return NSSize(width: 240, height: 120)
        case .noMicrophone:
            return NSSize(width: 240, height: 120)
        }
    }
}
