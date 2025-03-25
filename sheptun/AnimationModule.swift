import SwiftUI


/// Animation for transcribing state - simple pulsing dots
public struct TranscribingAnimation: View {
    // Animation parameters
    private let dotCount = 5
    private let dotSize: CGFloat = 8
    private let spacing: CGFloat = 12
    
    // Animation timing
    @State private var animating = false
    
    public init() {}
    
    public var body: some View {
        HStack(spacing: spacing) {
            ForEach(0..<dotCount, id: \.self) { index in
                Circle()
                    .fill(Color.blue)
                    .frame(width: dotSize, height: dotSize)
                    .scaleEffect(animating ? 1.5 : 0.5)
                    .opacity(animating ? 1.0 : 0.3)
                    .animation(
                        Animation.easeInOut(duration: 0.6)
                            .repeatForever(autoreverses: true)
                            .delay(Double(index) * 0.2),
                        value: animating
                    )
            }
        }
        .frame(height: 40)
        .onAppear {
            animating = true
        }
        .onDisappear {
            animating = false
        }
    }
}
