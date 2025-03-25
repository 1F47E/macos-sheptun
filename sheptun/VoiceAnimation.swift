import SwiftUI

/// A clean, responsive animation for voice recording that shows audio levels with dots
public struct VoiceAnimation: View {
    /// The intensity value (0.0 to 1.0) representing audio level
    public let intensity: Float
    
    // Constants
    private let dotCount = 50
    private let baseDotSize: CGFloat = 5
    private let maxDotSize: CGFloat = 10
    private let baseSpacing: CGFloat = 4
    private let verticalSpread: CGFloat = 20
    private let lowThreshold: Float = 0.05
    private let animationSpeed: Double = 2.0
    
    // Color
    private let dotColor = Color.blue
    
    public init(intensity: Float) {
        self.intensity = max(0, min(1, intensity))
    }
    
    public var body: some View {
        HStack(spacing: baseSpacing) {
            ForEach(0..<dotCount, id: \.self) { index in
                DotView(
                    index: index,
                    intensity: intensity,
                    lowThreshold: lowThreshold,
                    baseDotSize: baseDotSize,
                    maxDotSize: maxDotSize,
                    verticalSpread: verticalSpread,
                    dotColor: dotColor,
                    animationSpeed: animationSpeed
                )
            }
        }
        .frame(height: 40)
        .animation(.easeOut(duration: 0.2), value: intensity)
    }
}

/// Individual dot in the voice animation
private struct DotView: View {
    let index: Int
    let intensity: Float
    let lowThreshold: Float
    let baseDotSize: CGFloat
    let maxDotSize: CGFloat
    let verticalSpread: CGFloat
    let dotColor: Color
    let animationSpeed: Double
    
    @State private var phase: Double = 0
    
    private var dotSize: CGFloat {
        let factor = pow(Double(intensity), 1.5)
        return baseDotSize + (maxDotSize - baseDotSize) * CGFloat(factor)
    }
    
    private var dotOffset: CGFloat {
        // Calculate vertical offset based on intensity
        let verticalOffset = intensity > lowThreshold ? 
            sin(phase + Double(index) * 0.3) * Double(intensity) * Double(verticalSpread) :
            0
            
        return CGFloat(verticalOffset)
    }
    
    private var dotOpacity: Double {
        return intensity < lowThreshold ? 0.6 : 0.8 + Double(intensity) * 0.2
    }
    
    var body: some View {
        Circle()
            .fill(dotColor)
            .frame(width: dotSize, height: dotSize)
            .offset(y: dotOffset)
            .opacity(dotOpacity)
            .shadow(color: dotColor.opacity(0.5), radius: 2, x: 0, y: 1)
            .onAppear {
                // Start animation from a random phase
                phase = Double.random(in: 0...2 * .pi)
                
                // Continuous left-to-right animation
                withAnimation(
                    .linear(duration: animationSpeed)
                    .repeatForever(autoreverses: false)
                ) {
                    phase += 2 * .pi
                }
            }
    }
}

struct VoiceAnimation_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 30) {
            VoiceAnimation(intensity: 0)
                .previewDisplayName("No Sound")
                .frame(width: 200, height: 60)
                .background(Color.black.opacity(0.8))
                .cornerRadius(10)
            
            VoiceAnimation(intensity: 0.2)
                .previewDisplayName("Low Volume")
                .frame(width: 200, height: 60)
                .background(Color.black.opacity(0.8))
                .cornerRadius(10)
            
            VoiceAnimation(intensity: 0.5)
                .previewDisplayName("Medium Volume")
                .frame(width: 200, height: 60)
                .background(Color.black.opacity(0.8))
                .cornerRadius(10)
            
            VoiceAnimation(intensity: 1.0)
                .previewDisplayName("High Volume")
                .frame(width: 200, height: 60)
                .background(Color.black.opacity(0.8))
                .cornerRadius(10)
        }
        .padding()
        .previewLayout(.sizeThatFits)
    }
}