import SwiftUI

/// A set of horizontal "wave" lines that remain gently animated at low intensity,
/// becoming more wavy as intensity increases. By default, all lines share the same Y coordinate.
public struct VoiceAnimation: View {
    /// 0.0 = minimal wave, 1.0 = max wave
    public let intensity: Float
    
    /// The total height of the view
    private let containerHeight: CGFloat = 60
    /// The total width of the view
    private let containerWidth: CGFloat = 300
    
    /// The number of wave lines
    private let waveCount = 3
    
    /// We'll animate over time with a timer
    @State private var time: Double = 0
    
    /// Each wave line has random frequency & initial phase
    private let waves: [WaveLine]
    
    /// Vertical spacing between lines. Currently set to 0, so they're on the same line.
    private let lineSpacing: CGFloat = 10
    
    // MARK: - Initialization
    
    public init(intensity: Float) {
        // Clamp intensity to [0..1]
        let clamped = max(0, min(1, intensity))
        self.intensity = clamped
        
        // Create wave lines with random frequency/phase
        self.waves = (0..<waveCount).map { _ in
            WaveLine(
                frequency: Double.random(in: 0.3...0.7),
                phase: Double.random(in: 0 ..< 2 * .pi)
            )
        }
    }
    public var body: some View {
        ZStack {
            ForEach(0..<waveCount, id: \.self) { i in
                WaveShape(
                    wave: waves[i],
                    lineIndex: i,
                    waveCount: waveCount,
                    containerWidth: containerWidth,
                    containerHeight: containerHeight,
                    time: time,
                    intensity: intensity,
                    lineSpacing: lineSpacing
                )
                .stroke(Color.blue, lineWidth: 1)
            }
        }
        .frame(width: containerWidth, height: containerHeight)
        // Update our `time` at ~60 fps
        .onReceive(Timer.publish(every: 1/60, on: .main, in: .common).autoconnect()) { _ in
            time += 1/60
        }
    }
}

// MARK: - WaveLine Model

/// Defines the randomness of each wave line.
private struct WaveLine {
    let frequency: Double
    let phase: Double
}

/// A Shape that draws one horizontal wave line
private struct WaveShape: Shape {
    let wave: WaveLine
    let lineIndex: Int
    let waveCount: Int
    
    let containerWidth: CGFloat
    let containerHeight: CGFloat
    
    let time: Double
    let intensity: Float
    
    /// Vertical spacing between lines
    let lineSpacing: CGFloat
    
    func path(in rect: CGRect) -> Path {
        var path = Path()
        
        // The center Y for all lines is the middle of the container.
        let centerY = containerHeight / 2
        
        // Currently, lineSpacing = 0 => all lines overlap exactly.
        // If you want to spread them out, increase `lineSpacing`.
        // e.g., let offsetIndex = CGFloat(lineIndex) - CGFloat(waveCount - 1)/2
        // let lineCenterY = centerY + offsetIndex * lineSpacing
        let lineCenterY = centerY
        
        // Base amplitude is small at zero intensity. Grows with intensity.
        let baseAmplitude: CGFloat = 2
        let maxAmplitude: CGFloat = 10
        let amplitude = baseAmplitude + maxAmplitude * CGFloat(intensity)
        
        // We'll let the wave "wobble" over time at a certain speed
        let wobbleSpeed = 0.1
        
        // Start the wave at x=0
        path.move(to: CGPoint(x: 0, y: lineCenterY))
        
        // Draw from x=0 to x=containerWidth in small steps
        let step: CGFloat = 2
        
        for x in stride(from: 0, through: containerWidth, by: step) {
            // wave function: sin(frequency * x + phase + time * wobbleSpeed)
            let theta = wave.frequency * x + wave.phase + time * wobbleSpeed
            let y = lineCenterY + sin(theta) * amplitude
            path.addLine(to: CGPoint(x: x, y: y))
        }
        
        return path
    }
}

// MARK: - Preview

struct VoiceAnimation_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 30) {
            VoiceAnimation(intensity: 0)
                .previewDisplayName("Intensity 0")
                .background(Color.black.opacity(0.8))
                .cornerRadius(8)
            
            VoiceAnimation(intensity: 0.3)
                .previewDisplayName("Intensity 0.3")
                .background(Color.black.opacity(0.8))
                .cornerRadius(8)
            
            VoiceAnimation(intensity: 0.6)
                .previewDisplayName("Intensity 0.6")
                .background(Color.black.opacity(0.8))
                .cornerRadius(8)
            
            VoiceAnimation(intensity: 1.0)
                .previewDisplayName("Intensity 1.0")
                .background(Color.black.opacity(0.8))
                .cornerRadius(8)
        }
        .frame(width: 300, height: 500)
        .padding()
        .previewLayout(.sizeThatFits)
    }
}
