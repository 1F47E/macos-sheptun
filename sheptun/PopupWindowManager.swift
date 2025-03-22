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
            
            // Debug volume level
            Text("Volume: \(String(format: "%.2f", audioRecorder.audioLevel))")
                .font(.system(size: 13, design: .monospaced))
                .foregroundColor(.gray)
            
            // Timer display
            Text(formatTime(audioRecorder.recordingTime))
                .font(.system(size: 24, weight: .medium, design: .monospaced))
                .foregroundColor(.white)
            
            // Audio visualization with flowing dots
            FlowingDotsVisualization(audioLevel: audioRecorder.audioLevel)
                .frame(height: 50)
                .padding(.horizontal)
            
            Text("Speak now...")
                .font(.system(size: 14))
                .foregroundColor(.gray)
                .padding(.bottom, 5)
        }
        .frame(width: 400, height: 200)
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

// Flowing dots visualization that move from left to right
struct FlowingDotsVisualization: View {
    let audioLevel: Float
    private let dotCount = 40
    @State private var positions: [CGPoint] = []
    @State private var timer: Timer?
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Draw the flowing dots
                ForEach(0..<min(positions.count, dotCount), id: \.self) { index in
                    Circle()
                        .fill(dotColor(index: index))
                        .frame(width: dotSize(index: index), height: dotSize(index: index))
                        .position(positions[index])
                        .opacity(0.8)
                }
            }
            .onAppear {
                // Initialize dot positions
                initializeDots(in: geometry.size)
                
                // Start animation timer - more frequent updates for better responsiveness
                timer = Timer.scheduledTimer(withTimeInterval: 0.03, repeats: true) { _ in
                    updateDotPositions(in: geometry.size)
                }
            }
            .onDisappear {
                timer?.invalidate()
                timer = nil
            }
            .onChange(of: geometry.size) { _, newSize in
                // Reinitialize if size changes
                initializeDots(in: newSize)
            }
        }
    }
    
    // Dynamic dot size based on audio level and position
    private func dotSize(index: Int) -> CGFloat {
        let baseSize: CGFloat = 4.0
        let volumeBoost = CGFloat(audioLevel) * 4.0
        
        // Dots near the middle of the wave (by index) can be slightly larger
        let positionFactor = 1.0 - abs(CGFloat(index % 10) - 5.0) / 5.0
        
        return baseSize + (volumeBoost * positionFactor)
    }
    
    // Dynamic color based on audio level
    private func dotColor(index: Int) -> Color {
        // Base color gets more intense with higher audio levels
        let volume = Double(audioLevel)
        
        // Create vibrant color variations based on volume
        let hue = 0.6 - (volume * 0.5) // Transition from blue to purple/red as volume increases
        let saturation = 0.7 + (volume * 0.3) // More saturated at higher volumes
        let brightness = 0.7 + (volume * 0.3) // Brighter at higher volumes
        
        return Color(hue: hue, saturation: saturation, brightness: brightness)
    }
    
    private func initializeDots(in size: CGSize) {
        // Create initial positions for dots
        positions = (0..<dotCount).map { i in
            let x = CGFloat.random(in: 0...size.width)
            // When initializing, place all dots close to center line
            let y = size.height / 2 + CGFloat.random(in: -3...3)
            return CGPoint(x: x, y: y)
        }
    }
    
    private func updateDotPositions(in size: CGSize) {
        // Make spread more dramatic for better visualization of audio levels
        let minSpread: CGFloat = 3
        let maxSpread: CGFloat = size.height * 0.8 // Use even more of the available height
        
        // Apply non-linear scaling to make quiet sounds more visible and loud sounds more dramatic
        // More aggressive power curve for more pronounced effect at higher volumes
        let scaledAudioLevel = pow(CGFloat(audioLevel), 0.5) // Less than linear for better low-volume response
        let spread = minSpread + scaledAudioLevel * (maxSpread - minSpread)
        
        // Update each dot's position
        positions = positions.enumerated().map { index, position in
            var newPos = position
            
            // Move dots from left to right at consistent speed
            let baseSpeed: CGFloat = 2.0
            newPos.x += baseSpeed
            
            // If a dot goes off the right edge, reset it to the left
            if newPos.x > size.width {
                newPos.x = 0
                // Randomize vertical position within spread range
                newPos.y = size.height/2 + CGFloat.random(in: -spread...spread)
            }
            
            // Calculate how far across the screen this dot is (0.0 to 1.0)
            let progressAcrossScreen = newPos.x / size.width
            
            // Each dot gets a unique phase offset based on its index
            let uniqueOffset = Double(index) * 0.5
            
            // Wave properties affected by audio level
            let baseFrequency = 2.0 + Double(audioLevel) * 5.0 // Higher frequency at higher volumes
            let wavePhase = Date().timeIntervalSince1970 * baseFrequency + uniqueOffset
            
            // Each dot gets a unique amplitude modifier to create more varied movement
            let dotAmplitudeModifier = 0.5 + sin(Double(index) * 0.3) * 0.5
            
            // Multiple wave components for more chaotic/organic movement at higher volumes
            let primaryWave = sin(wavePhase)
            let secondaryWave = cos(wavePhase * 1.3) * 0.4 * Double(audioLevel)
            let tertiaryWave = sin(wavePhase * 2.5) * 0.3 * Double(audioLevel * audioLevel)
            
            // Combine waves with more components at higher volumes
            let combinedWave = primaryWave + secondaryWave + tertiaryWave
            
            // More pronounced wave effect at higher audio levels
            let volumeImpact = spread * CGFloat(dotAmplitudeModifier)
            let waveFactor = combinedWave * Double(volumeImpact)
            
            // Add some random jitter to dots based on audio level
            let jitter = CGFloat.random(in: -1.0...1.0) * CGFloat(audioLevel) * 3.0
            
            // Calculate target Y position with wave effect and jitter
            let targetY = size.height/2 + CGFloat(waveFactor) + jitter
            
            // Faster response for dots when volume is higher
            let baseAdaptationSpeed: CGFloat = 0.2
            let volumeAdaptationBoost: CGFloat = 0.6
            let adaptationSpeed = baseAdaptationSpeed + (CGFloat(audioLevel) * volumeAdaptationBoost)
            
            // Apply movement - dots that are further along their journey (closer to right edge)
            // get more dramatic vertical movement
            let verticalMovementFactor = baseAdaptationSpeed + (progressAcrossScreen * adaptationSpeed)
            newPos.y = newPos.y + (targetY - newPos.y) * verticalMovementFactor
            
            return newPos
        }
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