import Cocoa
import SwiftUI

class PopupWindowManager {
    static let shared = PopupWindowManager()
    
    private var popupWindow: NSWindow?
    private let logger = Logger.shared
    
    private init() {}
    
    func showPopupWindow() {
        // If window already exists, just show it
        if let window = popupWindow {
            logger.log("Reusing existing popup window", level: .debug)
            positionWindowAtTopCenter(window)
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        
        logger.log("Creating new popup window", level: .info)
        
        // Create a window without standard decorations
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 100),
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
        let hostingView = NSHostingView(rootView: RecordingPromptView())
        window.contentView = hostingView
        
        // Position window at top center of the screen
        positionWindowAtTopCenter(window)
        
        // Show window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        
        // Set a timer to automatically close the window after 10 seconds of inactivity
        Timer.scheduledTimer(withTimeInterval: 10, repeats: false) { [weak self] _ in
            self?.closePopupWindow()
        }
        
        self.popupWindow = window
    }
    
    func closePopupWindow() {
        if let window = popupWindow {
            window.close()
            popupWindow = nil
            logger.log("Popup window closed", level: .debug)
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
}

// SwiftUI view for the popup window
struct RecordingPromptView: View {
    var body: some View {
        VStack {
            Text("Say something...")
                .font(.system(size: 18, weight: .medium))
                .foregroundColor(.white)
                .padding()
        }
        .frame(width: 300, height: 100)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(red: 0.2, green: 0.2, blue: 0.2, opacity: 0.9))
        )
        .shadow(color: Color.black.opacity(0.3), radius: 10, x: 0, y: 5)
    }
} 