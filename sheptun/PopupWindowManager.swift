//
//  PopupWindowManager.swift
//  sheptun
//
//  Created by Example on 2025-03-26.
//

import Cocoa
import SwiftUI
import Foundation
// import GRDB // Make sure to add this package dependency!
import AVFoundation // For AVAudioPlayer later

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
                    // --- History Saving START ---
                    // TODO: Re-enable after adding GRDB dependency
                    /*
                    Task { // Run saving in a separate Task to not block UI updates
                        do {
                            let persistentURL = try await DatabaseManager.shared.saveAudioFile(recordedFileURL)
                            let historyItem = HistoryItem(
                                timestamp: Date(),
                                audioFilePath: persistentURL.path,
                                transcription: transcription
                            )
                            try await DatabaseManager.shared.saveHistoryItem(item: historyItem)
                            self.logger.log("Successfully saved transcription to history.", level: .info)
                            // Optionally delete the original temp file if desired
                            // try? FileManager.default.removeItem(at: recordedFileURL)
                        } catch {
                            self.logger.error("Failed to save transcription history: \(error.localizedDescription)")
                            // Decide how to handle this - maybe show a non-blocking error?
                        }
                    }
                    */
                    // --- History Saving END ---

                    // Copy result to clipboard
                    self.logger.log("Copying transcription to clipboard", level: .info)
                    NSPasteboard.general.clearContents()
                    let success = NSPasteboard.general.setString(transcription, forType: .string)
                    self.logger.log("Clipboard setString result: \(success)", level: .info)
                    
                    // Verify clipboard content
                    if let clipboardCheck = NSPasteboard.general.string(forType: .string) {
                        self.logger.log("Verified clipboard content (first 50 chars): \(String(clipboardCheck.prefix(50)))...", level: .info)
                    } else {
                        self.logger.log("ERROR: Failed to verify clipboard content!", level: .error)
                    }
                    
                    // Post notification for test result tracking
                    NotificationCenter.default.post(
                        name: NSNotification.Name("TranscriptionCompleted"),
                        object: nil,
                        userInfo: ["transcription": transcription]
                    )
                    
                    // Only auto-paste if enabled in settings
                    self.logger.log("Checking auto-paste setting: \(self.settingsManager.autoPasteTranscription)", level: .info)
                    if self.settingsManager.autoPasteTranscription {
                        self.logger.log("Auto-paste is enabled, calling simulatePasteAndClose()", level: .info)
                        self.simulatePasteAndClose()
                    } else {
                        self.logger.log("Auto-paste is disabled, just closing popup", level: .info)
                        self.closePopup()
                    }
                    
                case .failure(let error):
                    self.currentState = .error("Transcription failed: \(error.localizedDescription)")
                    
                    // Report to Sentry
                    SentryManager.shared.captureError(error, context: [
                        "provider": self.settingsManager.selectedProvider,
                        "model": self.settingsManager.transcriptionModel,
                        "microphone": self.settingsManager.selectedMicrophoneID
                    ])
                }
            }
        }
    }
    
    private func simulatePasteAndClose() {
        logger.log("simulatePasteAndClose() called", level: .info)
        
        // 1) Close the popup immediately
        closePopup()
        logger.log("Popup closed, scheduling paste event after 0.5s delay", level: .info)

        // 2) Then post Cmd+V after delay - increased delay for reliability
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self = self else { 
                Logger.shared.log("Self was deallocated before paste event", level: .error)
                return 
            }
            
            self.logger.log("Timer fired, attempting to post Cmd+V event", level: .info)
            
            // Check if we have accessibility permissions
            let accessibilityEnabled = AXIsProcessTrusted()
            self.logger.log("Accessibility permissions: \(accessibilityEnabled ? "GRANTED" : "NOT GRANTED")", level: .info)
            
            if !accessibilityEnabled {
                self.logger.log("ERROR: App needs accessibility permissions to paste. Opening System Settings...", level: .error)
                // Open accessibility settings
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                    NSWorkspace.shared.open(url)
                }
                return
            }
            
            // Log current clipboard content
            if let clipboardContent = NSPasteboard.general.string(forType: .string) {
                self.logger.log("Clipboard content (first 50 chars): \(String(clipboardContent.prefix(50)))...", level: .info)
            } else {
                self.logger.log("WARNING: Clipboard is empty!", level: .warning)
            }

            guard let source = CGEventSource(stateID: .combinedSessionState) else {
                self.logger.log("Failed to create CGEventSource for Cmd+V", level: .error)
                return
            }
            
            self.logger.log("CGEventSource created successfully", level: .debug)

            // Virtual key code 0x09 is 'V'
            let cmdVDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true)
            cmdVDown?.flags = .maskCommand

            let cmdVUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false)
            cmdVUp?.flags = .maskCommand

            // Check if events were created before posting
            if let downEvent = cmdVDown, let upEvent = cmdVUp {
                self.logger.log("CGEvents created successfully, posting Cmd+V", level: .info)
                
                // Try different event tap locations
                let tapLocations: [CGEventTapLocation] = [.cgSessionEventTap, .cghidEventTap, .cgAnnotatedSessionEventTap]
                var posted = false
                
                for location in tapLocations {
                    self.logger.log("Trying to post to tap location: \(location.rawValue)", level: .debug)
                    downEvent.post(tap: location)
                    Thread.sleep(forTimeInterval: 0.01) // Small delay between key down and up
                    upEvent.post(tap: location)
                    posted = true
                    break // Use first location that works
                }
                
                if posted {
                    self.logger.log("Cmd+V events posted successfully", level: .info)
                } else {
                    self.logger.log("Failed to post Cmd+V events to any tap location", level: .error)
                }
            } else {
                self.logger.log("Failed to create CGEvent for Cmd+V - events are nil", level: .error)
            }
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
        VStack(spacing: 8) {
            // Main content area
            switch manager.currentState {
            case .recording:
                // Clean audio waveform similar to AudioSettingsView
                CleanAudioWaveform(audioLevel: audioRecorder.audioLevel)
                    .frame(width: 140, height: 40)
                
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
                // Error icon and message
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
                .padding(.horizontal)
                
            case .noMicrophone:
                // Microphone error
                Image(systemName: "mic.slash.fill")
                    .font(.title2)
                    .foregroundColor(.red)
            }
            
            // Status text at bottom
            statusText
                .font(.caption)
                .foregroundColor(.white.opacity(0.7))
                .padding(.bottom, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    @ViewBuilder
    private var statusText: some View {
        switch manager.currentState {
        case .recording:
            Text("Recording...")
        case .transcribing:
            Text("Transcribing...")
        case .completed:
            Text("Done")
        case .error:
            Text("Error")
        case .noMicrophone:
            Text("No Microphone")
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
            return NSSize(width: 160, height: 80)  // Increased height for status text
        case .error:
            return NSSize(width: 240, height: 120)
        case .noMicrophone:
            return NSSize(width: 160, height: 80)  // Simplified size
        }
    }
}

// MARK: - Clean Audio Waveform

struct CleanAudioWaveform: View {
    let audioLevel: Float
    @State private var phase: CGFloat = 0
    
    var body: some View {
        GeometryReader { geometry in
            Canvas { context, size in
                let width = size.width
                let height = size.height
                let midY = height / 2
                
                // Draw a smooth sine wave
                var path = Path()
                
                // Number of wave cycles
                let frequency: CGFloat = 3.0
                
                // Amplitude based on audio level
                let minAmplitude: CGFloat = 2.0
                let maxAmplitude: CGFloat = height * 0.4
                let amplitude = minAmplitude + (maxAmplitude - minAmplitude) * CGFloat(audioLevel)
                
                // Draw the wave
                for x in stride(from: 0, to: width, by: 1) {
                    let relativeX = x / width
                    let y = midY + sin((relativeX * frequency * .pi * 2) + phase) * amplitude
                    
                    if x == 0 {
                        path.move(to: CGPoint(x: x, y: y))
                    } else {
                        path.addLine(to: CGPoint(x: x, y: y))
                    }
                }
                
                // Apply gradient stroke
                let gradient = Gradient(colors: [
                    Color.green.opacity(0.8),
                    Color.green,
                    Color.green.opacity(0.8)
                ])
                
                context.stroke(
                    path,
                    with: .linearGradient(
                        gradient,
                        startPoint: CGPoint(x: 0, y: midY),
                        endPoint: CGPoint(x: width, y: midY)
                    ),
                    lineWidth: 2
                )
            }
        }
        .onAppear {
            // Smooth continuous animation
            withAnimation(.linear(duration: 2).repeatForever(autoreverses: false)) {
                phase = .pi * 2
            }
        }
    }
}

// TODO: Re-enable after adding GRDB dependency
/*
// Defines the structure for a single history record
struct HistoryItem: Identifiable, Codable { // FetchableRecord, PersistableRecord {
    var id: Int64? // Primary key, auto-incremented by the database
    var timestamp: Date // When the recording was made
    var audioFilePath: String // Path to the saved audio file
    var transcription: String // The transcription text

    // Standard GRDB setup to map columns and define table name
    enum Columns {
        static let id = Column(CodingKeys.id)
        static let timestamp = Column(CodingKeys.timestamp)
        static let audioFilePath = Column(CodingKeys.audioFilePath)
        static let transcription = Column(CodingKeys.transcription)
    }

    static var databaseTableName = "historyItem"

    // Called by GRDB after a successful insertion
    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

class DatabaseManager {
    static let shared = DatabaseManager()
    private let logger = Logger.shared
    // private var dbQueue: DatabaseQueue!

    private init() {
        setupDatabase()
    }

    // MARK: - Database Setup

    private func setupDatabase() {
        do {
            let databaseURL = try FileManager.default
                .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
                .appendingPathComponent("sheptun.sqlite")

            // TODO: Re-enable after adding GRDB dependency
            // dbQueue = try DatabaseQueue(path: databaseURL.path)
            logger.log("Database queue initialized at: \(databaseURL.path)", level: .info)

            // Run migrations to create tables if they don't exist
            // try runMigrations()

        } catch {
            logger.log("Failed to initialize database: \(error.localizedDescription)", level: .critical)
            // Consider how to handle this fatal error in a real app
            fatalError("Database setup failed: \(error)")
        }
    }

    private func runMigrations() throws {
        // TODO: Re-enable after adding GRDB dependency
        /*
        var migrator = DatabaseMigrator()

        // v1: Create the initial historyItem table
        migrator.registerMigration("v1_createHistoryItem") { db in
            try db.create(table: HistoryItem.databaseTableName) { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("timestamp", .datetime).notNull().indexed()
                t.column("audioFilePath", .text).notNull()
                t.column("transcription", .text).notNull()
            }
        }

        // Add future migrations here if the schema changes
        // migrator.registerMigration("v2_...") { db in ... }

        // Apply migrations
        try migrator.migrate(dbQueue)
        */
        logger.log("Database migrations completed successfully.", level: .info)
    }

    // MARK: - Audio File Management

    /// Copies the temporary recording file to a persistent location in App Support.
    /// Returns the URL of the *newly saved* file.
    func saveAudioFile(_ sourceURL: URL) async throws -> URL {
        let fileManager = FileManager.default
        let appSupportDir = try fileManager.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let recordingsDir = appSupportDir.appendingPathComponent("Recordings", isDirectory: true)

        // Create Recordings directory if it doesn't exist
        if !fileManager.fileExists(atPath: recordingsDir.path) {
            try fileManager.createDirectory(at: recordingsDir, withIntermediateDirectories: true, attributes: nil)
            logger.log("Created Recordings directory at: \(recordingsDir.path)", level: .info)
        }

        // Create a unique filename (e.g., using timestamp and UUID)
        let timestamp = Int(Date().timeIntervalSince1970)
        let uniqueFilename = "recording_\(timestamp)_\(UUID().uuidString).\(sourceURL.pathExtension)"
        let destinationURL = recordingsDir.appendingPathComponent(uniqueFilename)

        // Perform the copy
        do {
            try fileManager.copyItem(at: sourceURL, to: destinationURL)
            logger.log("Copied recording from \(sourceURL.path) to \(destinationURL.path)", level: .debug)
            return destinationURL
        } catch {
            logger.log("Failed to copy audio file: \(error.localizedDescription)", level: .error)
            throw error // Re-throw the error to be handled by the caller
        }
    }

    // MARK: - History Item CRUD

    /// Saves a HistoryItem record to the database.
    func saveHistoryItem(item: HistoryItem) async throws {
        // TODO: Re-enable after adding GRDB dependency
        /*
        try await dbQueue.write { db in
            var itemToSave = item // Make mutable copy
            try itemToSave.save(db)
             logger.log("Saved history item with ID: \(itemToSave.id ?? -1)", level: .debug)
        }
        */
    }

    /// Fetches all history items, ordered by timestamp descending.
    func fetchHistoryItems() async throws -> [HistoryItem] {
        // TODO: Re-enable after adding GRDB dependency
        /*
        try await dbQueue.read { db in
            try HistoryItem
                .order(HistoryItem.Columns.timestamp.desc)
                .fetchAll(db)
        }
        */
        return []
    }

     /// Deletes a specific history item and its associated audio file.
    func deleteHistoryItem(item: HistoryItem) async throws {
        // TODO: Re-enable after adding GRDB dependency
        /*
        let filePath = item.audioFilePath
        try await dbQueue.write { db in
            _ = try item.delete(db) // Delete database record
            logger.log("Deleted history item with ID: \(item.id ?? -1) from DB.", level: .debug)
        }
        // Delete the audio file after DB record is gone
        do {
             try FileManager.default.removeItem(atPath: filePath)
             logger.log("Deleted audio file: \(filePath)", level: .debug)
         } catch {
             logger.log("Failed to delete audio file \(filePath): \(error.localizedDescription). DB record was deleted.", level: .warning)
             // Decide if this error needs propagation or just logging
         }
        */
    }

    /// Deletes ALL history items and their associated audio files. Use with caution!
    func deleteAllHistory() async throws {
        // TODO: Re-enable after adding GRDB dependency
        /*
        let allItems = try await fetchHistoryItems() // Get paths before deleting records
        try await dbQueue.write { db in
            _ = try HistoryItem.deleteAll(db)
             logger.log("Deleted all history items from DB.", level: .info)
        }
         // Delete all audio files
        for item in allItems {
            do {
                try FileManager.default.removeItem(atPath: item.audioFilePath)
            } catch {
                 logger.log("Failed to delete audio file \(item.audioFilePath) during deleteAll: \(error.localizedDescription)", level: .warning)
            }
        }
         logger.log("Attempted deletion of all associated audio files.", level: .info)
        */
    }
}
*/ // End of DatabaseManager and HistoryItem comment block
