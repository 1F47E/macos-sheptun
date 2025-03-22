import Cocoa
import SwiftUI

class PopupWindowManager {
    static let shared = PopupWindowManager()
    
    private var popupWindow: NSWindow?
    private let logger = Logger.shared
    private let audioRecorder = AudioRecorder.shared
    private var audioLevelSimulationTimer: Timer?
    
    private init() {}
    
    var isWindowVisible: Bool {
        return popupWindow != nil && popupWindow!.isVisible
    }
    
    func togglePopupWindow() {
        if isWindowVisible {
            closePopupWindow()
            logger.log("Popup window toggled off", level: .info)
        } else {
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
        
        // Start audio recording
        audioRecorder.startRecording()
        
        // Start simulating audio levels in case real audio isn't available
        startAudioLevelSimulation()
        
        // Keep a reference to the window
        self.popupWindow = window
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
    
    var body: some View {
        VStack(spacing: 12) {
            Text("Recording Session")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(.white)
            
            // Timer display
            Text(formatTime(audioRecorder.recordingTime))
                .font(.system(size: 24, weight: .medium, design: .monospaced))
                .foregroundColor(.white)
            
            // Audio level visualization
            HStack(spacing: 2) {
                ForEach(0..<20, id: \.self) { index in
                    AudioBar(index: index, level: audioRecorder.audioLevel)
                }
            }
            .frame(height: 40)
            .padding(.horizontal)
            
            Text("Speak now...")
                .font(.system(size: 14))
                .foregroundColor(.gray)
                .padding(.bottom, 5)
        }
        .frame(width: 400, height: 180)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(red: 0.1, green: 0.1, blue: 0.1, opacity: 0.95))
        )
        .shadow(color: Color.black.opacity(0.4), radius: 10, x: 0, y: 5)
    }
    
    private func formatTime(_ timeInterval: TimeInterval) -> String {
        let minutes = Int(timeInterval) / 60
        let seconds = Int(timeInterval) % 60
        let milliseconds = Int((timeInterval.truncatingRemainder(dividingBy: 1)) * 100)
        return String(format: "%02d:%02d.%02d", minutes, seconds, milliseconds)
    }
}

struct AudioBar: View {
    let index: Int
    let level: Float
    
    var body: some View {
        let threshold = Float(index) / 20.0 * 1.1 // Make the scale slightly greater than 1 for visual appeal
        let isActive = level >= threshold
        
        RoundedRectangle(cornerRadius: 2)
            .fill(barColor(isActive: isActive, index: index))
            .frame(width: 10)
            .scaleEffect(y: isActive ? 1.0 : 0.3, anchor: .bottom)
            .animation(.spring(response: 0.15, dampingFraction: 0.35, blendDuration: 0.1), value: isActive)
    }
    
    private func barColor(isActive: Bool, index: Int) -> Color {
        if !isActive {
            return Color.gray.opacity(0.3)
        }
        
        // Create a gradient effect from green to yellow to red
        if index < 10 {
            return Color.green
        } else if index < 16 {
            return Color.yellow
        } else {
            return Color.red
        }
    }
} 