import SwiftUI

/// A responsive animation with two modes: voice recording and loading.
/// Seamlessly transitions between the two modes.
public struct ParticleWaveEffect: View {
    // MARK: - Constants
    
    // Animation parameters
    private let kMinIntensityForWave: Float = 0.2
    private let kWaveHeightFactor: CGFloat = 0.4
    private let kWaveSegments: Int = 20
    private let kWaveOpacityBase: CGFloat = 0.2
    private let kWaveOpacityFactor: CGFloat = 0.1
    private let kWaveLineWidthBase: CGFloat = 2
    private let kWaveLineWidthFactor: CGFloat = 3
    
    // Global animation speed
    private let kAnimationPhaseIncrement: Double = 0.05
    private let kTransitionProgressIncrement: Double = 0.05
    private let kLoadingPhaseIncrement: Double = 0.01
    
    // Voice particles
    private let kVoiceParticleCount: Int = 30
    private let kVoiceParticleSpreadBase: CGFloat = 10
    private let kVoiceParticleSpreadFactor: CGFloat = 10
    private let kVoiceParticleSizeMin: CGFloat = 3
    private let kVoiceParticleSizeMax: CGFloat = 12
    private let kVoiceParticleSizeBaseFactor: CGFloat = 0.5
    private let kVoiceParticleSizeIntensityFactor: CGFloat = 0.5
    private let kVoiceParticleSpeedBase: CGFloat = 1.0
    private let kVoiceParticleSpeedRandomMax: CGFloat = 0.8
    private let kVoiceParticleSpeedIntensityFactor: CGFloat = 2
    private let kVoiceParticleOpacityMin: Double = 0.5
    private let kVoiceParticleOpacityMax: Double = 0.9
    private let kVoiceParticleHorizontalSpawnRange: ClosedRange<CGFloat> = -10...0
    private let kVoiceParticleVerticalSpread: CGFloat = 5
    
    // Loading particles
    private let kLoadingParticleCount: Int = 3
    private let kLoadingCircleRadiusFactor: CGFloat = 0.3
    private let kLoadingParticleSize: CGFloat = 3.0
    private let kLoadingParticleSpeed: CGFloat = 0.2
    private let kLoadingParticleOpacity: Double = 0.8
    
    // Transitions
    private let kMaxTransitionParticles: Int = 12
    private let kTransitionParticleVerticalRange: ClosedRange<CGFloat> = -20...20
    private let kTransitionParticleSize: CGFloat = 6.0
    private let kTransitionParticleSpeed: CGFloat = 0.3
    private let kTransitionOpacityDecrement: Double = 0.1
    private let kMaxRemainingParticles: Int = 5
    private let kTransitionRandomMovementRange: ClosedRange<CGFloat> = -5...5
    private let kTransitionMidPoint: Double = 0.5
    private let kTransitionNewParticleFactor: Int = 5
    private let kTransitionVoiceSpeedBase: CGFloat = 1.0
    private let kTransitionVoiceSpeedRandomMax: CGFloat = 0.2
    
    // Pulse effect
    private let kPulseScaleBase: Double = 1.0
    private let kPulseScaleFactor: Double = 0.2
    private let kPulseFrequency: Double = 1.2
    private let kOpacityBase: Double = 0.7
    private let kOpacityVariation: Double = 0.3
    private let kOpacityFrequency: Double = 1.5
    private let kColorMixSpeedFactor: Double = 0.02
    
    // Voice movement
    private let kVoiceSpreadBase: CGFloat = 10
    private let kVoiceSpreadHeightFactor: CGFloat = 0.3
    private let kVoiceSpeedBase: CGFloat = 0.5
    private let kVoiceSpeedRandomMax: CGFloat = 0.3
    private let kVoiceWaveAmplitudeDivisor: CGFloat = 12
    private let kVoiceWaveFrequencyBase: CGFloat = 1.0
    
    // Color thresholds
    private let kLowIntensityThreshold: Double = 0.3
    private let kHighIntensityThreshold: Double = 0.7
    private let kColorBlendThreshold: CGFloat = 0.7
    private let kLowIntensityOpacityBase: Double = 0.7
    private let kLowIntensityOpacityFactor: Double = 0.3
    
    // MARK: - Public Properties
    
    /// The intensity value (0.0 to 1.0) that drives the animation
    public let intensity: Float
    
    // MARK: - Mode Control
    
    /// Controls whether the animation is in loading mode
    @State public var isLoading: Bool = false
    
    // MARK: - Fixed Properties
    @State private var baseColor: Color = .blue
    @State private var accentColor: Color = .purple
    
    // MARK: - Private Properties
    @State private var particles: [Particle] = []
    @State private var animationPhase: Double = 0
    @State private var isFirstAppear: Bool = true
    @State private var loadingPhase: Double = 0
    @State private var transitionProgress: Double = 0
    
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
                    if intensity > kMinIntensityForWave {
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
                        if particle.size > kVoiceParticleSizeMax * 0.5 && intensity > 0.5 {
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
                    var mutableSelf = self
                    mutableSelf.updateParticles(in: geometry.size)
                }
                .onChange(of: geometry.size) { _, newSize in
                    // Reset if container size changes
                    var mutableSelf = self
                    mutableSelf.resetParticles(in: newSize)
                }
                .onChange(of: isLoading) { oldValue, newValue in
                    // Begin transition between modes
                    if oldValue != newValue {
                        var mutableSelf = self
                        mutableSelf.startModeTransition(to: newValue, in: geometry.size)
                    }
                }
                .onAppear {
                    if isFirstAppear {
                        // Initialize on first appear
                        var mutableSelf = self
                        mutableSelf.resetParticles(in: geometry.size)
                        mutableSelf.isFirstAppear = false
                    }
                }
            }
        }
    }
    
    // MARK: - Public Methods
    
    /// Toggle loading mode
    /// - Parameter isLoading: Whether loading mode should be enabled
    public mutating func setLoadingMode(_ isLoading: Bool) {
        self.isLoading = isLoading
    }
    
    // MARK: - Private Methods
    
    /// Draw a subtle background wave effect
    private func drawBackgroundWave(in context: GraphicsContext, size: CGSize) {
        let waveHeight = size.height * CGFloat(intensity) * kWaveHeightFactor
        let segments = kWaveSegments
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
        waveContext.opacity = kWaveOpacityBase + (CGFloat(intensity) * kWaveOpacityFactor)
        waveContext.stroke(
            path,
            with: .linearGradient(
                Gradient(colors: [baseColor, accentColor]),
                startPoint: CGPoint(x: 0, y: size.height/2),
                endPoint: CGPoint(x: size.width, y: size.height/2)
            ),
            lineWidth: kWaveLineWidthBase + CGFloat(intensity) * kWaveLineWidthFactor
        )
    }
    
    /// Reset and reinitialize all particles
    private mutating func resetParticles(in size: CGSize) {
        particles = []
        loadingPhase = 0
        transitionProgress = 0
        
        // Create particles based on current mode
        if isLoading {
            createLoadingParticles(in: size)
        } else {
            createVoiceParticles(in: size)
        }
    }
    
    /// Create particles for voice recording mode
    private mutating func createVoiceParticles(in size: CGSize) {
        let particleCount = kVoiceParticleCount
        
        for _ in 0..<particleCount {
            let x = CGFloat.random(in: 0...size.width)
            let centerY = size.height / 2
            let spread = kVoiceParticleSpreadBase + CGFloat(intensity) * kVoiceParticleSpreadFactor
            let y = centerY + CGFloat.random(in: -spread...spread)
            
            // Base size on intensity
            let particleSize = CGFloat.random(in: kVoiceParticleSizeMin...kVoiceParticleSizeMax) * 
                (kVoiceParticleSizeBaseFactor + CGFloat(intensity) * kVoiceParticleSizeIntensityFactor)
            let particleSpeed = kVoiceParticleSpeedBase + 
                CGFloat.random(in: 0...kVoiceParticleSpeedRandomMax) * CGFloat(intensity) * kVoiceParticleSpeedIntensityFactor
            
            // Create color based on intensity
            let particleColor = getParticleColor(intensity: intensity, random: CGFloat.random(in: 0...1))
            
            particles.append(Particle(
                position: CGPoint(x: x, y: y),
                size: particleSize,
                speed: particleSpeed,
                phase: Double.random(in: 0...2 * .pi),
                color: particleColor,
                opacity: Double.random(in: kVoiceParticleOpacityMin...kVoiceParticleOpacityMax)
            ))
        }
    }
    
    /// Create particles for loading mode
    private mutating func createLoadingParticles(in size: CGSize) {
        // In loading mode, create particles arranged in a circle
        let particleCount = kLoadingParticleCount
        let centerX = size.width / 2
        let centerY = size.height / 2
        let radius = min(size.width, size.height) * kLoadingCircleRadiusFactor
        
        for i in 0..<particleCount {
            let angle = (Double(i) / Double(particleCount)) * 2 * .pi
            let x = centerX + cos(angle) * radius
            let y = centerY + sin(angle) * radius
            
            // Create a particle with properties suitable for loading animation
            let particleSize = kLoadingParticleSize
            let particleSpeed = kLoadingParticleSpeed
            
            // Alternate colors for visual interest
            let colorMix = Double(i) / Double(particleCount)
            let particleColor = interpolateColor(from: baseColor, to: accentColor, amount: colorMix)
            
            particles.append(Particle(
                position: CGPoint(x: x, y: y),
                size: particleSize,
                speed: particleSpeed,
                phase: angle, // Use angle as phase for smooth loading animation
                color: particleColor,
                opacity: kLoadingParticleOpacity
            ))
        }
    }
    
    /// Start transition between modes
    private mutating func startModeTransition(to newLoadingState: Bool, in size: CGSize) {
        // Reset transition progress
        transitionProgress = 0
        
        // Keep existing particles during transition
        // The updateParticles method will handle the transition animation
    }
    
    /// Update particle properties for the next animation frame
    private mutating func updateParticles(in size: CGSize) {
        // Increment global animation phase
        animationPhase += kAnimationPhaseIncrement
        
        // Handle mode transition if needed
        if isLoading && transitionProgress < 1.0 {
            // Transition to loading mode
            transitionProgress += kTransitionProgressIncrement
            updateTransitionToLoading(in: size)
        } else if !isLoading && transitionProgress < 1.0 {
            // Transition to voice recording mode
            transitionProgress += kTransitionProgressIncrement
            updateTransitionToVoice(in: size)
        } else if isLoading {
            // Regular loading mode update
            updateLoadingMode(in: size)
        } else {
            // Regular voice recording mode update
            updateVoiceMode(in: size)
        }
    }
    
    /// Update particles during transition to loading mode
    private mutating func updateTransitionToLoading(in size: CGSize) {
        // If transition is complete, reset to loading mode
        if transitionProgress >= 1.0 {
            particles = []
            createLoadingParticles(in: size)
            transitionProgress = 1.0
            return
        }
        
        let centerX = size.width / 2
        let centerY = size.height / 2
        let targetRadius = min(size.width, size.height) * kLoadingCircleRadiusFactor
        
        // If we need more particles for a proper loading animation, add them
        if particles.count < kMaxTransitionParticles {
            let needed = kMaxTransitionParticles - particles.count
            for i in 0..<needed {
                // Add new particles that start from random positions
                let randomX = CGFloat.random(in: 0...size.width)
                let randomY = size.height / 2 + CGFloat.random(in: kTransitionParticleVerticalRange)
                
                let angle = (Double(particles.count + i) / Double(kMaxTransitionParticles)) * 2 * .pi
                let colorMix = Double(particles.count + i) / Double(kMaxTransitionParticles)
                
                particles.append(Particle(
                    position: CGPoint(x: randomX, y: randomY),
                    size: kTransitionParticleSize,
                    speed: kTransitionParticleSpeed,
                    phase: angle,
                    color: interpolateColor(from: baseColor, to: accentColor, amount: colorMix),
                    opacity: kLoadingParticleOpacity
                ))
            }
        }
        
        // Move existing particles toward their loading position
        for i in 0..<particles.count {
            let normalizedIndex = Double(i % kMaxTransitionParticles) / Double(kMaxTransitionParticles)
            let targetAngle = normalizedIndex * 2 * .pi
            
            // Calculate target position in the circle
            let targetX = centerX + cos(targetAngle) * targetRadius
            let targetY = centerY + sin(targetAngle) * targetRadius
            
            // Interpolate current position toward target
            let progress = CGFloat(transitionProgress)
            let newX = particles[i].position.x + (targetX - particles[i].position.x) * progress
            let newY = particles[i].position.y + (targetY - particles[i].position.y) * progress
            
            // Update particle
            var updatedParticle = particles[i]
            updatedParticle.position = CGPoint(x: newX, y: newY)
            updatedParticle.size = particles[i].size + (kTransitionParticleSize - particles[i].size) * progress
            updatedParticle.color = interpolateColor(
                from: particles[i].color,
                to: interpolateColor(from: baseColor, to: accentColor, amount: normalizedIndex),
                amount: progress
            )
            
            particles[i] = updatedParticle
        }
        
        // If we have too many particles, gradually fade out excess ones
        if particles.count > kMaxRemainingParticles {
            for i in kMaxRemainingParticles..<particles.count {
                var particle = particles[i]
                particle.opacity = max(0, particle.opacity - kTransitionOpacityDecrement)
                particles[i] = particle
            }
            
            // Remove completely faded particles
            particles = particles.filter { $0.opacity > 0 }
        }
    }
    
    /// Update particles during transition to voice recording mode
    private mutating func updateTransitionToVoice(in size: CGSize) {
        // If transition is complete, reset to voice mode
        if transitionProgress >= 1.0 {
            particles = []
            createVoiceParticles(in: size)
            transitionProgress = 1.0
            return
        }
        
        // Gradually disperse the loading circle particles
        for i in 0..<particles.count {
            var particle = particles[i]
            
            // Add some random movement to break the circle
            let randomX = CGFloat.random(in: kTransitionRandomMovementRange) * CGFloat(transitionProgress)
            let randomY = CGFloat.random(in: kTransitionRandomMovementRange) * CGFloat(transitionProgress)
            
            particle.position.x += randomX
            particle.position.y += randomY
            
            // Gradually adjust size based on intensity
            let targetSize = CGFloat.random(in: kVoiceParticleSizeMin...kVoiceParticleSizeMax) * 
                (kVoiceParticleSizeBaseFactor + CGFloat(intensity) * kVoiceParticleSizeIntensityFactor)
            particle.size = particle.size + (targetSize - particle.size) * CGFloat(transitionProgress)
            
            // Update color
            particle.color = getParticleColor(intensity: intensity, random: CGFloat.random(in: 0...1))
            
            particles[i] = particle
        }
        
        // Add new particles to transition toward voice mode
        if transitionProgress > kTransitionMidPoint && particles.count < kVoiceParticleCount {
            let particlesToAdd = Int(transitionProgress * CGFloat(kTransitionNewParticleFactor))
            
            for _ in 0..<particlesToAdd {
                let x = CGFloat.random(in: 0...size.width)
                let centerY = size.height / 2
                let spread = kVoiceParticleSpreadBase + CGFloat(intensity) * kVoiceParticleSpreadFactor
                let y = centerY + CGFloat.random(in: -spread...spread)
                
                let particleSize = CGFloat.random(in: kVoiceParticleSizeMin...kVoiceParticleSizeMax) * 
                    (kVoiceParticleSizeBaseFactor + CGFloat(intensity) * kVoiceParticleSizeIntensityFactor)
                let particleSpeed = kTransitionVoiceSpeedBase + 
                    CGFloat.random(in: 0...kTransitionVoiceSpeedRandomMax) * CGFloat(intensity) * kVoiceParticleSpeedIntensityFactor
                let particleColor = getParticleColor(intensity: intensity, random: CGFloat.random(in: 0...1))
                
                // Start with low opacity and fade in
                let opacity = Double(transitionProgress) - kTransitionMidPoint
                
                if opacity > 0 && particles.count < kVoiceParticleCount {
                    particles.append(Particle(
                        position: CGPoint(x: x, y: y),
                        size: particleSize,
                        speed: particleSpeed,
                        phase: Double.random(in: 0...2 * .pi),
                        color: particleColor,
                        opacity: opacity
                    ))
                }
            }
        }
    }
    
    /// Update particles in loading mode
    private mutating func updateLoadingMode(in size: CGSize) {
        // Increment loading phase
        loadingPhase += kLoadingPhaseIncrement
        
        let centerX = size.width / 2
        let centerY = size.height / 2
        let radius = min(size.width, size.height) * kLoadingCircleRadiusFactor
        
        // Update each particle in the loading circle
        for i in 0..<particles.count {
            var particle = particles[i]
            
            // Calculate base position in the circle
            let normalizedIndex = Double(i) / Double(particles.count)
            let angle = normalizedIndex * 2 * .pi + loadingPhase
            
            // Calculate position with rotation
            let x = centerX + cos(angle) * radius
            let y = centerY + sin(angle) * radius
            
            // Apply pulsing effect
            let pulseScale = kPulseScaleBase + sin(loadingPhase * kPulseFrequency + normalizedIndex * .pi) * kPulseScaleFactor
            
            // Update particle
            particle.position = CGPoint(x: x, y: y)
            particle.size = kTransitionParticleSize * pulseScale
            particle.opacity = kOpacityBase + sin(loadingPhase * kOpacityFrequency + normalizedIndex * .pi * 2) * kOpacityVariation
            
            // Gradually shift colors for visual interest
            let colorMix = (normalizedIndex + loadingPhase * kColorMixSpeedFactor).truncatingRemainder(dividingBy: 1.0)
            particle.color = interpolateColor(from: baseColor, to: accentColor, amount: colorMix)
            
            particles[i] = particle
        }
    }
    
    /// Update particles in voice recording mode
    private mutating func updateVoiceMode(in size: CGSize) {
        // Calculate wave parameters based on intensity
        let centerY = size.height / 2
        let spread = kVoiceSpreadBase + CGFloat(intensity) * (size.height * kVoiceSpreadHeightFactor)
        
        // Update each particle
        for i in 0..<particles.count {
            var particle = particles[i]
            
            // Horizontal movement
            particle.position.x += particle.speed
            
            // Reset position when particle goes off-screen
            if particle.position.x > size.width {
                particle.position.x = 0
                
                // Update properties for the new cycle
                particle.size = CGFloat.random(in: kVoiceParticleSizeMin...kVoiceParticleSizeMax) * 
                    (kVoiceParticleSizeBaseFactor + CGFloat(intensity) * kVoiceParticleSizeIntensityFactor)
                particle.speed = kVoiceSpeedBase + 
                    CGFloat.random(in: 0...kVoiceSpeedRandomMax) * CGFloat(intensity) * kVoiceParticleSpeedIntensityFactor
                particle.color = getParticleColor(intensity: intensity, random: CGFloat.random(in: 0...1))
                particle.opacity = Double.random(in: kVoiceParticleOpacityMin...kVoiceParticleOpacityMax)
            }
            
            // Vertical movement with wave pattern
            let waveAmplitude = spread * (particle.size / kVoiceWaveAmplitudeDivisor)
            let waveFrequency = kVoiceWaveFrequencyBase + (particle.size / kVoiceWaveAmplitudeDivisor)
            let yOffset = sin(
                (particle.phase + Double(particle.position.x) / Double(size.width) * 4 * .pi + animationPhase) * waveFrequency
            ) * Double(waveAmplitude)
            
            particle.position.y = centerY + CGFloat(yOffset)
            
            // Update particle in array
            particles[i] = particle
        }
        
        // Add new particles if needed
        while particles.count < kVoiceParticleCount {
            let x = CGFloat.random(in: kVoiceParticleHorizontalSpawnRange) // Start just off-screen
            let centerY = size.height / 2
            let spread = kVoiceParticleVerticalSpread
            let y = centerY + CGFloat.random(in: -spread...spread)
            
            let particleSize = CGFloat.random(in: kVoiceParticleSizeMin...kVoiceParticleSizeMax) * 
                (kVoiceParticleSizeBaseFactor + CGFloat(intensity) * kVoiceParticleSizeIntensityFactor)
            let particleSpeed = kVoiceSpeedBase + 
                CGFloat.random(in: 0...kVoiceSpeedRandomMax) * CGFloat(intensity) * kVoiceParticleSpeedIntensityFactor
            let particleColor = getParticleColor(intensity: intensity, random: CGFloat.random(in: 0...1))
            
            particles.append(Particle(
                position: CGPoint(x: x, y: y),
                size: particleSize,
                speed: particleSpeed,
                phase: Double.random(in: 0...2 * .pi),
                color: particleColor,
                opacity: Double.random(in: kVoiceParticleOpacityMin...kVoiceParticleOpacityMax)
            ))
        }
    }
    
    /// Get a color for a particle based on intensity and randomness
    private func getParticleColor(intensity: Float, random: CGFloat) -> Color {
        let energyLevel = Double(intensity)
        
        // At low intensity, use mostly base color
        if energyLevel < kLowIntensityThreshold {
            return baseColor.opacity(kLowIntensityOpacityBase + Double(random) * kLowIntensityOpacityFactor)
        } 
        // At medium intensity, blend between base and accent
        else if energyLevel < kHighIntensityThreshold {
            return random > kColorBlendThreshold ? accentColor : baseColor
        } 
        // At high intensity, create more vibrant colors
        else {
            return interpolateColor(from: baseColor, to: accentColor, amount: Double(random))
        }
    }
    
    /// Interpolate between two colors
    private func interpolateColor(from color1: Color, to color2: Color, amount: Double) -> Color {
        let nsColor1 = NSColor(color1)
        let nsColor2 = NSColor(color2)
        
        // Extract RGB components
        var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
        var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
        
        nsColor1.getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        nsColor2.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        
        // Interpolate
        let r = r1 + (r2 - r1) * CGFloat(amount)
        let g = g1 + (g2 - g1) * CGFloat(amount)
        let b = b1 + (b2 - b1) * CGFloat(amount)
        let a = a1 + (a2 - a1) * CGFloat(amount)
        
        // Create new color
        return Color(NSColor(red: r, green: g, blue: b, alpha: a))
    }
}

// MARK: - Builder Pattern Extension

public extension ParticleWaveEffect {
    /// Enable or disable loading mode
    func loadingMode(_ isLoading: Bool) -> ParticleWaveEffect {
        let copy = self
        var mutableCopy = copy
        mutableCopy.isLoading = isLoading
        return mutableCopy
    }
}

// MARK: - Preview

struct ParticleWaveEffect_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 20) {
            ParticleWaveEffect(intensity: 0.2)
                .padding()
                .background(Color.black.opacity(0.1))
                .cornerRadius(8)
            
            ParticleWaveEffect(intensity: 0.5)
                .loadingMode(true)
                .padding()
                .background(Color.black.opacity(0.1))
                .cornerRadius(8)
            
            ParticleWaveEffect(intensity: 0.8)
                .padding()
                .background(Color.black.opacity(0.1))
                .cornerRadius(8)
        }
        .padding()
    }
} 