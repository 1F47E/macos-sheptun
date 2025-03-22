import SwiftUI

/// A responsive particle animation that visualizes numeric values between 0 and 1.
/// Useful for audio levels, progress indicators, or any real-time data visualization.
public struct ParticleWaveEffect: View {
    // MARK: - Public Properties
    
    /// The intensity value (0.0 to 1.0) that drives the animation
    public let intensity: Float
    
    // MARK: - Customization Options
    
    /// Number of particles in the effect
    public var particleCount: Int = 35
    
    /// Base color for particles (modified based on intensity)
    public var baseColor: Color = .blue
    
    /// Secondary color for creating gradients
    public var accentColor: Color = .purple
    
    /// Fixed height for the animation container
    public var height: CGFloat? = nil
    
    /// Max particle size
    public var maxParticleSize: CGFloat = 12
    
    // MARK: - Private Properties
    @State private var particles: [Particle] = []
    @State private var lastIntensity: Float = 0
    @State private var animationPhase: Double = 0
    @State private var isFirstAppear: Bool = true
    
    // Data structure for each particle
    private struct Particle: Identifiable {
        let id = UUID()
        var position: CGPoint
        var size: CGFloat
        var speed: CGFloat
        var phase: Double
        var color: Color
        var opacity: Double
    }
    
    // MARK: - Initialization
    
    /// Creates a new particle wave effect
    /// - Parameter intensity: Value between 0.0 and 1.0 driving the animation
    public init(intensity: Float) {
        self.intensity = max(0, min(1, intensity))
    }
    
    // MARK: - Body
    
    public var body: some View {
        TimelineView(.animation) { timeline in
            GeometryReader { geometry in
                Canvas { context, size in
                    // Draw background wave if intensity is high enough
                    if intensity > 0.2 {
                        drawBackgroundWave(in: context, size: size)
                    }
                    
                    // Draw all particles
                    for particle in particles {
                        let path = Path(ellipseIn: CGRect(
                            x: particle.position.x - particle.size/2,
                            y: particle.position.y - particle.size/2,
                            width: particle.size,
                            height: particle.size
                        ))
                        
                        var particleContext = context
                        particleContext.opacity = particle.opacity
                        particleContext.fill(path, with: .color(particle.color))
                        
                        // Add glow effect for larger particles
                        if particle.size > maxParticleSize * 0.5 && intensity > 0.5 {
                            var glowContext = context
                            glowContext.opacity = particle.opacity * 0.5
                            glowContext.blendMode = .screen
                            glowContext.fill(
                                path.strokedPath(StrokeStyle(lineWidth: 2)), 
                                with: .color(particle.color)
                            )
                        }
                    }
                }
                .onChange(of: timeline.date) { _, _ in
                    // Update animation state
                    updateParticles(in: geometry.size)
                }
                .onChange(of: geometry.size) { _, newSize in
                    // Reset if container size changes
                    resetParticles(in: newSize)
                }
                .onChange(of: intensity) { oldValue, newValue in
                    // React to intensity changes
                    if abs(oldValue - newValue) > 0.1 {
                        updateParticleColors()
                        
                        // Add burst of particles on significant increases
                        if newValue > oldValue + 0.3 {
                            addEnergyBurst(in: geometry.size)
                        }
                    }
                }
                .onAppear {
                    if isFirstAppear {
                        // Initialize on first appear
                        resetParticles(in: geometry.size)
                        isFirstAppear = false
                    }
                }
            }
            .frame(height: height)
        }
    }
    
    // MARK: - Private Methods
    
    /// Draw a subtle background wave effect
    private func drawBackgroundWave(in context: GraphicsContext, size: CGSize) {
        let waveHeight = size.height * CGFloat(intensity) * 0.4
        let segments = 20
        let segmentWidth = size.width / CGFloat(segments)
        
        var path = Path()
        path.move(to: CGPoint(x: 0, y: size.height/2))
        
        for i in 0...segments {
            let x = CGFloat(i) * segmentWidth
            let angle = Double(x) / Double(size.width) * .pi * 4 + animationPhase
            let y = size.height/2 + sin(angle) * waveHeight
            path.addLine(to: CGPoint(x: x, y: y))
        }
        
        var waveContext = context
        waveContext.opacity = 0.2 + (CGFloat(intensity) * 0.1)
        waveContext.stroke(
            path,
            with: .linearGradient(
                Gradient(colors: [baseColor, accentColor]),
                startPoint: CGPoint(x: 0, y: size.height/2),
                endPoint: CGPoint(x: size.width, y: size.height/2)
            ),
            lineWidth: 2 + CGFloat(intensity) * 3
        )
    }
    
    /// Create a burst of particles when intensity suddenly increases
    private func addEnergyBurst(in size: CGSize) {
        let burstCount = Int(CGFloat(intensity) * 5)
        let centerY = size.height / 2
        
        for _ in 0..<burstCount {
            let x = CGFloat.random(in: size.width * 0.3...size.width * 0.7)
            let y = centerY + CGFloat.random(in: -20...20)
            let burstSize = maxParticleSize * CGFloat.random(in: 0.7...1.0) * CGFloat(intensity)
            let burstSpeed = 2.0 + CGFloat.random(in: 0...1.5) * CGFloat(intensity)
            
            let particleColor = getParticleColor(intensity: intensity, random: CGFloat.random(in: 0...1))
            
            let newParticle = Particle(
                position: CGPoint(x: x, y: y),
                size: burstSize,
                speed: burstSpeed,
                phase: Double.random(in: 0...2 * .pi),
                color: particleColor,
                opacity: Double.random(in: 0.7...1.0)
            )
            
            if particles.count < particleCount * 2 {
                particles.append(newParticle)
            }
        }
    }
    
    /// Reset and reinitialize all particles
    private func resetParticles(in size: CGSize) {
        particles = []
        
        // Create initial set of particles
        for _ in 0..<particleCount {
            let x = CGFloat.random(in: 0...size.width)
            let centerY = size.height / 2
            let spread = CGFloat(10 + intensity * 10)
            let y = centerY + CGFloat.random(in: -spread...spread)
            
            // Base size on intensity
            let particleSize = CGFloat.random(in: 3...maxParticleSize) * (0.5 + CGFloat(intensity) * 0.5)
            let particleSpeed = 1.0 + CGFloat.random(in: 0...0.8) * CGFloat(intensity) * 2
            
            // Create color based on intensity
            let particleColor = getParticleColor(intensity: intensity, random: CGFloat.random(in: 0...1))
            
            particles.append(Particle(
                position: CGPoint(x: x, y: y),
                size: particleSize,
                speed: particleSpeed,
                phase: Double.random(in: 0...2 * .pi),
                color: particleColor,
                opacity: Double.random(in: 0.5...0.9)
            ))
        }
        
        updateParticleColors()
        lastIntensity = intensity
    }
    
    /// Update particle properties for the next animation frame
    private func updateParticles(in size: CGSize) {
        // Increment global animation phase
        animationPhase += 0.05
        
        // Calculate wave parameters based on intensity
        let centerY = size.height / 2
        let spread = 10 + CGFloat(intensity) * (size.height * 0.3)
        
        // Update each particle
        for i in 0..<particles.count {
            // Horizontal movement
            var particle = particles[i]
            particle.position.x += particle.speed
            
            // Reset position when particle goes off-screen
            if particle.position.x > size.width {
                particle.position.x = 0
                
                // Update size and speed based on current intensity
                particle.size = CGFloat.random(in: 3...maxParticleSize) * (0.5 + CGFloat(intensity) * 0.5)
                particle.speed = 1.0 + CGFloat.random(in: 0...0.8) * CGFloat(intensity) * 2
                particle.color = getParticleColor(intensity: intensity, random: CGFloat.random(in: 0...1))
                particle.opacity = Double.random(in: 0.5...0.9)
            }
            
            // Vertical movement with wave pattern
            let waveAmplitude = spread * (particle.size / maxParticleSize)
            let waveFrequency = 1.0 + (particle.size / maxParticleSize)
            let yOffset = sin(
                (particle.phase + Double(particle.position.x) / Double(size.width) * 4 * .pi + animationPhase) * waveFrequency
            ) * Double(waveAmplitude)
            
            particle.position.y = centerY + CGFloat(yOffset)
            
            // Update particle in array
            particles[i] = particle
        }
        
        // Clean up excess particles
        if particles.count > particleCount * 2 {
            particles.removeFirst(particles.count - particleCount * 2)
        }
        
        // Check if intensity has changed significantly
        if abs(intensity - lastIntensity) > 0.1 {
            updateParticleColors()
            lastIntensity = intensity
        }
    }
    
    /// Update particle colors based on the current intensity
    private func updateParticleColors() {
        // Update colors for all particles
        for i in 0..<particles.count {
            var particle = particles[i]
            particle.color = getParticleColor(intensity: intensity, random: CGFloat.random(in: 0...1))
            particles[i] = particle
        }
    }
    
    /// Get a color for a particle based on intensity and randomness
    private func getParticleColor(intensity: Float, random: CGFloat) -> Color {
        let energyLevel = Double(intensity)
        
        // At low intensity, use mostly base color
        if energyLevel < 0.3 {
            return baseColor.opacity(0.7 + Double(random) * 0.3)
        } 
        // At medium intensity, blend between base and accent
        else if energyLevel < 0.7 {
            return random > 0.7 ? accentColor : baseColor
        } 
        // At high intensity, create more vibrant colors
        else {
            // Create vibrant variations
            let hue = baseColor.hsbComponents.hue + (random * 0.2) - 0.1 + (energyLevel * 0.1)
            let saturation = min(1.0, baseColor.hsbComponents.saturation + (energyLevel * 0.2))
            let brightness = min(1.0, baseColor.hsbComponents.brightness + (energyLevel * 0.3))
            
            return Color(hue: hue, saturation: saturation, brightness: brightness)
        }
    }
}

// MARK: - Builder Pattern Extensions

public extension ParticleWaveEffect {
    /// Sets the number of particles to display
    func particleCount(_ count: Int) -> ParticleWaveEffect {
        var copy = self
        copy.particleCount = count
        return copy
    }
    
    /// Sets the base color for particles
    func baseColor(_ color: Color) -> ParticleWaveEffect {
        var copy = self
        copy.baseColor = color
        return copy
    }
    
    /// Sets the accent color for particles and effects
    func accentColor(_ color: Color) -> ParticleWaveEffect {
        var copy = self
        copy.accentColor = color
        return copy
    }
    
    /// Sets the height of the visualization
    func height(_ height: CGFloat) -> ParticleWaveEffect {
        var copy = self
        copy.height = height
        return copy
    }
    
    /// Sets the maximum particle size
    func maxParticleSize(_ size: CGFloat) -> ParticleWaveEffect {
        var copy = self
        copy.maxParticleSize = size
        return copy
    }
}

// MARK: - Color Extensions

extension Color {
    /// Returns the HSB (Hue, Saturation, Brightness) components of a color
    var hsbComponents: (hue: Double, saturation: Double, brightness: Double) {
        // Create safe defaults in case conversion fails
        let defaults = (hue: 0.5, saturation: 0.7, brightness: 0.7)
        
        // Try to extract HSB components directly
        let color = NSColor(self)
        
        // Attempt to convert to calibrated RGB first which is more reliable for HSB conversion
        guard let rgbColor = color.usingColorSpace(.sRGB) else {
            return defaults
        }
        
        // Extract RGB components
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        rgbColor.getRed(&r, green: &g, blue: &b, alpha: &a)
        
        // Manually convert RGB to HSB
        let max = Swift.max(r, g, b)
        let min = Swift.min(r, g, b)
        let delta = max - min
        
        // Calculate brightness
        let brightness = max
        
        // Calculate saturation
        let saturation = max > 0 ? delta / max : 0
        
        // Calculate hue
        var hue: CGFloat = 0
        if delta > 0 {
            if max == r {
                hue = (g - b) / delta + (g < b ? 6 : 0)
            } else if max == g {
                hue = (b - r) / delta + 2
            } else { // max == b
                hue = (r - g) / delta + 4
            }
            hue /= 6
        }
        
        return (hue: Double(hue), saturation: Double(saturation), brightness: Double(brightness))
    }
}

// MARK: - Preview

struct ParticleWaveEffect_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 20) {
            ParticleWaveEffect(intensity: 0.2)
                .baseColor(.blue)
                .accentColor(.purple)
                .height(60)
                .padding()
                .background(Color.black.opacity(0.1))
                .cornerRadius(8)
            
            ParticleWaveEffect(intensity: 0.5)
                .baseColor(.green)
                .accentColor(.teal)
                .height(60)
                .padding()
                .background(Color.black.opacity(0.1))
                .cornerRadius(8)
            
            ParticleWaveEffect(intensity: 0.8)
                .baseColor(.red)
                .accentColor(.orange)
                .height(60)
                .padding()
                .background(Color.black.opacity(0.1))
                .cornerRadius(8)
        }
        .padding()
    }
} 