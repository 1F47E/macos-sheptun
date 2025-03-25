import SwiftUI

/// A responsive particle animation that visualizes numeric values between 0 and 1.
/// Useful for audio levels, progress indicators, or any real-time data visualization.
public struct ParticleWaveEffect: View {
    // MARK: - Public Properties
    
    /// The intensity value (0.0 to 1.0) that drives the animation
    public let intensity: Float
    
    // MARK: - Customization Options
    
    /// Number of particles in the effect
    public var particleCount: Int = 42
    
    /// Base color for particles (modified based on intensity)
    @State public var baseColor: Color = .blue
    
    /// Secondary color for creating gradients
    @State public var accentColor: Color = .purple
    
    /// Fixed height for the animation container
    public var height: CGFloat? = nil
    
    /// Max particle size
    public var maxParticleSize: CGFloat = 12
    
    /// Amount of color variation (0.0 to 1.0)
    @State public var colorVariationIntensity: Float = 1.0
    
    /// Animation speed multiplier (0.5 to 2.0, where 1.0 is normal speed)
    @State public var animationSpeed: Float = 1.0
    
    /// Wave amplitude multiplier (0.5 to 2.0, where 1.0 is normal amplitude)
    @State public var waveAmplitudeMultiplier: Float = 1.0
    
    /// Particle density distribution (0.0 for uniform, 1.0 for more intensity-weighted)
    @State public var particleDensity: Float = 0.5
    
    /// Controls whether the background wave line is shown
    @State public var showWaveLine: Bool = true
    
    /// Controls whether particles change colors based on intensity
    @State public var enableColorChanges: Bool = true
    
    /// Controls whether particles change size based on intensity
    @State public var enableSizeChanges: Bool = true
    
    /// Controls whether particles move horizontally
    @State public var enableMovement: Bool = true
    
    /// Controls whether the animation is in loading mode
    @State public var isLoading: Bool = false
    
    // MARK: - Private Properties
    @State private var particles: [Particle] = []
    @State private var lastIntensity: Float = 0
    @State private var animationPhase: Double = 0
    @State private var isFirstAppear: Bool = true
    @State private var loadedSettings: Bool = false
    @State private var loadingPhase: Double = 0
    
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
        
        // First try to load from JSON settings
        if let jsonString = UserDefaults.standard.string(forKey: "animationSettingsJSON"),
           let jsonData = jsonString.data(using: .utf8) {
            
            do {
                if let jsonSettings = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any] {
                    Logger.shared.log("Loading animation settings from JSON", level: .info)
                    
                    // Apply colors
                    if let redBase = jsonSettings["baseColorRed"] as? Double,
                       let greenBase = jsonSettings["baseColorGreen"] as? Double,
                       let blueBase = jsonSettings["baseColorBlue"] as? Double {
                        self.baseColor = Color(NSColor(red: CGFloat(redBase), green: CGFloat(greenBase), blue: CGFloat(blueBase), alpha: 1.0))
                        Logger.shared.log("Loaded base color from JSON", level: .debug)
                    }
                    
                    if let redAccent = jsonSettings["accentColorRed"] as? Double,
                       let greenAccent = jsonSettings["accentColorGreen"] as? Double,
                       let blueAccent = jsonSettings["accentColorBlue"] as? Double {
                        self.accentColor = Color(NSColor(red: CGFloat(redAccent), green: CGFloat(greenAccent), blue: CGFloat(blueAccent), alpha: 1.0))
                        Logger.shared.log("Loaded accent color from JSON", level: .debug)
                    }
                    
                    // Load other parameters
                    if let value = jsonSettings["colorVariationIntensity"] as? Double {
                        self.colorVariationIntensity = Float(value)
                    }
                    
                    if let value = jsonSettings["animationSpeed"] as? Double {
                        self.animationSpeed = Float(value)
                    }
                    
                    if let value = jsonSettings["waveAmplitudeMultiplier"] as? Double {
                        self.waveAmplitudeMultiplier = Float(value)
                    }
                    
                    if let value = jsonSettings["particleDensity"] as? Double {
                        self.particleDensity = Float(value)
                    }
                    
                    if let value = jsonSettings["showWaveLine"] as? Bool {
                        self.showWaveLine = value
                    }
                    
                    if let value = jsonSettings["enableColorChanges"] as? Bool {
                        self.enableColorChanges = value
                    }
                    
                    if let value = jsonSettings["enableSizeChanges"] as? Bool {
                        self.enableSizeChanges = value
                    }
                    
                    if let value = jsonSettings["enableMovement"] as? Bool {
                        self.enableMovement = value
                    }
                    
                    // isLoadingMode is not loaded from settings anymore
                    // Always start in normal mode
                    self.isLoading = false
                }
            } catch {
                Logger.shared.log("Failed to parse JSON settings: \(error)", level: .error)
            }
        }
        // Fall back to legacy settings if no JSON found
        else if let savedSettings = UserDefaults.standard.dictionary(forKey: "animationSettings") {
            Logger.shared.log("Found saved settings with key 'animationSettings' containing \(savedSettings.count) key-value pairs", level: .debug)
            Logger.shared.log("Settings contents: \(savedSettings)", level: .debug)
            
            // Apply saved settings if available
            if let colorVariation = savedSettings["colorVariationIntensity"] as? Double {
                self.colorVariationIntensity = Float(colorVariation)
                Logger.shared.log("Loaded colorVariationIntensity: \(colorVariation)", level: .debug)
            } else {
                Logger.shared.log("Missing colorVariationIntensity in settings", level: .debug)
            }
            
            if let speed = savedSettings["animationSpeed"] as? Double {
                self.animationSpeed = Float(speed)
                Logger.shared.log("Loaded animationSpeed: \(speed)", level: .debug)
            } else {
                Logger.shared.log("Missing animationSpeed in settings", level: .debug)
            }
            
            if let amplitude = savedSettings["waveAmplitudeMultiplier"] as? Double {
                self.waveAmplitudeMultiplier = Float(amplitude)
                Logger.shared.log("Loaded waveAmplitudeMultiplier: \(amplitude)", level: .debug)
            } else {
                Logger.shared.log("Missing waveAmplitudeMultiplier in settings", level: .debug)
            }
            
            if let density = savedSettings["particleDensity"] as? Double {
                self.particleDensity = Float(density)
                Logger.shared.log("Loaded particleDensity: \(density)", level: .debug)
            } else {
                Logger.shared.log("Missing particleDensity in settings", level: .debug)
            }
            
            if let showWave = savedSettings["showWaveLine"] as? Bool {
                self.showWaveLine = showWave
                Logger.shared.log("Loaded showWaveLine: \(showWave)", level: .debug)
            } else {
                Logger.shared.log("Missing showWaveLine in settings", level: .debug)
            }
            
            if let enableColors = savedSettings["enableColorChanges"] as? Bool {
                self.enableColorChanges = enableColors
                Logger.shared.log("Loaded enableColorChanges: \(enableColors)", level: .debug)
            } else {
                Logger.shared.log("Missing enableColorChanges in settings", level: .debug)
            }
            
            if let enableSizes = savedSettings["enableSizeChanges"] as? Bool {
                self.enableSizeChanges = enableSizes
                Logger.shared.log("Loaded enableSizeChanges: \(enableSizes)", level: .debug)
            } else {
                Logger.shared.log("Missing enableSizeChanges in settings", level: .debug)
            }
            
            if let enableMove = savedSettings["enableMovement"] as? Bool {
                self.enableMovement = enableMove
                Logger.shared.log("Loaded enableMovement: \(enableMove)", level: .debug)
            } else {
                Logger.shared.log("Missing enableMovement in settings", level: .debug)
            }
            
            // isLoadingMode is not loaded from settings anymore
            // Always start in normal mode
            self.isLoading = false
            
            // Load colors
            if let redBase = savedSettings["baseColorRed"] as? Double,
               let greenBase = savedSettings["baseColorGreen"] as? Double,
               let blueBase = savedSettings["baseColorBlue"] as? Double,
               let redAccent = savedSettings["accentColorRed"] as? Double,
               let greenAccent = savedSettings["accentColorGreen"] as? Double,
               let blueAccent = savedSettings["accentColorBlue"] as? Double {
                
                self.baseColor = Color(NSColor(red: CGFloat(redBase), green: CGFloat(greenBase), blue: CGFloat(blueBase), alpha: 1.0))
                self.accentColor = Color(NSColor(red: CGFloat(redAccent), green: CGFloat(greenAccent), blue: CGFloat(blueAccent), alpha: 1.0))
                
                Logger.shared.log("Loaded colors - base: (\(redBase), \(greenBase), \(blueBase)), accent: (\(redAccent), \(greenAccent), \(blueAccent))", level: .debug)
            } else {
                Logger.shared.log("Missing color values in settings - keys found: baseColorRed=\(savedSettings["baseColorRed"] != nil), baseColorGreen=\(savedSettings["baseColorGreen"] != nil), baseColorBlue=\(savedSettings["baseColorBlue"] != nil), accentColorRed=\(savedSettings["accentColorRed"] != nil), accentColorGreen=\(savedSettings["accentColorGreen"] != nil), accentColorBlue=\(savedSettings["accentColorBlue"] != nil)", level: .debug)
            }
            
            Logger.shared.log("Animation settings loaded successfully", level: .info)
        } else {
            Logger.shared.log("No saved settings found for ParticleWaveEffect, using defaults", level: .info)
        }
        
        // Setup notification observer for settings changes
        setupNotificationObserver()
    }
    
    // MARK: - Body
    
    public var body: some View {
        TimelineView(.animation) { timeline in
            GeometryReader { geometry in
                Canvas { context, size in
                    // Draw background wave if intensity is high enough and enabled
                    if intensity > 0.2 && showWaveLine {
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
                    var mutableSelf = self
                    mutableSelf.updateParticles(in: geometry.size)
                }
                .onChange(of: geometry.size) { _, newSize in
                    // Reset if container size changes
                    var mutableSelf = self
                    mutableSelf.resetParticles(in: newSize)
                }
                .onChange(of: intensity) { oldValue, newValue in
                    // React to intensity changes
                    if abs(oldValue - newValue) > 0.1 {
                        var mutableSelf = self
                        mutableSelf.updateParticleColors()
                        
                        // Add burst of particles on significant increases
                        if newValue > oldValue + 0.3 {
                            mutableSelf.addEnergyBurst(in: geometry.size)
                        }
                    }
                }
                .onChange(of: isLoading) { _, newValue in
                    // React to loading mode changes
                    var mutableSelf = self
                    mutableSelf.setLoadingMode(newValue)
                }
                .onAppear {
                    if isFirstAppear {
                        // Initialize on first appear
                        var mutableSelf = self
                        mutableSelf.resetParticles(in: geometry.size)
                        mutableSelf.isFirstAppear = false
                        
                        // Listen for settings changes
                        mutableSelf.setupNotificationObserver()
                        
                        // Apply initial loading mode if needed
                        if isLoading {
                            mutableSelf.setLoadingMode(true)
                        }
                    }
                }
                .onDisappear {
                    // Clean up notification observer when view disappears
                    NotificationCenter.default.removeObserver(
                        NotificationCenter.self,
                        name: NSNotification.Name("AnimationSettingsChanged"),
                        object: nil
                    )
                    Logger.shared.log("Removed notification observer from ParticleWaveEffect", level: .debug)
                }
            }
            .frame(height: height)
        }
    }
    
    // MARK: - Public Methods
    
    /// Toggle loading mode
    /// - Parameter isLoading: Whether loading mode should be enabled
    public mutating func setLoadingMode(_ isLoading: Bool) {
        // If no change, do nothing
        if self.isLoading == isLoading {
            return
        }
        
        self.isLoading = isLoading
        
        // Reset loading phase when toggling
        if isLoading {
            loadingPhase = 0
            
            // Keep only one particle for loading mode
            if particles.count > 0 {
                // Find a particle closest to center or create one near center
                let centerX = particles.first?.position.x ?? 50
                let centerY = particles.first?.position.y ?? 20
                
                // Create a particle that's near the center but not exactly at it
                // This allows for a smooth animation toward center
                let nearCenterPosition = CGPoint(
                    x: centerX + CGFloat.random(in: -30...30),
                    y: centerY + CGFloat.random(in: -10...10)
                )
                
                // Use an existing particle if possible
                var centerParticle = particles.first!
                centerParticle.position = nearCenterPosition
                
                // Set a good size for the loading indicator
                centerParticle.size = 8.0
                centerParticle.opacity = 0.8
                
                // Keep only this particle
                particles = [centerParticle]
            } else {
                // Create a single particle if none exists
                particles = [createRandomParticle(nearCenter: true)]
            }
        } else {
            // When exiting loading mode, ensure we have enough particles
            if particles.count < particleCount {
                let additionalNeeded = particleCount - particles.count
                
                for _ in 0..<additionalNeeded {
                    // Generate new particles off-screen to create a flowing-in effect
                    let newParticle = createRandomParticle(offScreen: true)
                    particles.append(newParticle)
                }
            }
        }
    }
    
    // Helper to create a random particle, optionally placing it off-screen or near center
    private func createRandomParticle(offScreen: Bool = false, nearCenter: Bool = false) -> Particle {
        let position: CGPoint
        let phase = Double.random(in: 0...2 * .pi)
        let size = CGFloat.random(in: 3...maxParticleSize) * (0.5 + CGFloat(intensity) * 0.5)
        let speed = 1.0 + CGFloat.random(in: 0...0.8) * CGFloat(intensity) * 2
        let color = getParticleColor(intensity: intensity, random: CGFloat.random(in: 0...1))
        let opacity = Double.random(in: 0.5...0.9)
        
        if nearCenter {
            // Position near but not exactly at center for smooth movement
            position = CGPoint(x: 50 + CGFloat.random(in: -20...20), 
                               y: 20 + CGFloat.random(in: -10...10))
        } else if offScreen {
            // Position just off the left edge
            position = CGPoint(x: -size, y: 20 + CGFloat.random(in: 0...20))
        } else {
            // Normal random position
            position = CGPoint(x: CGFloat.random(in: 0...100), y: 20 + CGFloat.random(in: -10...10))
        }
        
        return Particle(
            position: position,
            size: size,
            speed: speed,
            phase: phase,
            color: color,
            opacity: opacity
        )
    }
    
    // MARK: - Private Methods
    
    private mutating func setupNotificationObserver() {
        // Register for settings change notifications
        NotificationCenter.default.addObserver(forName: NSNotification.Name("AnimationSettingsChanged"), object: nil, queue: .main) { notification in
            Logger.shared.log("Received AnimationSettingsChanged notification in ParticleWaveEffect", level: .info)
            
            if let settings = notification.userInfo as? [String: Any] {
                Logger.shared.log("Updating animation with new settings", level: .debug)
                
                // Check if loading mode is specified in the notification
                if let isLoadingValue = settings["isLoadingMode"] as? Bool {
                    Logger.shared.log("Notification contains isLoadingMode: \(isLoadingValue)", level: .debug)
                    // Can't directly modify self here since notification callbacks are separate functions
                    // Store in UserDefaults for next animation frame to pick up
                    UserDefaults.standard.set(settings, forKey: "animationSettings")
                }
                
                // Store settings in UserDefaults for the next animation frame
                UserDefaults.standard.set(settings, forKey: "animationSettings")
                Logger.shared.log("Saved new settings to UserDefaults for next animation frame", level: .info)
            } else {
                Logger.shared.log("No settings found in notification", level: .warning)
            }
        }
        
        Logger.shared.log("Set up notification observer for settings changes", level: .debug)
    }
    
    // Method to update settings on running ParticleWaveEffect
    private mutating func updateLiveSettings(_ settings: [String: Any]) {
        // Apply settings directly to this instance
        if let colorVariation = settings["colorVariationIntensity"] as? Double {
            self.colorVariationIntensity = Float(colorVariation)
            Logger.shared.log("Updated colorVariationIntensity: \(colorVariation)", level: .debug)
        }
        
        if let speed = settings["animationSpeed"] as? Double {
            self.animationSpeed = Float(speed)
            Logger.shared.log("Updated animationSpeed: \(speed)", level: .debug)
        }
        
        if let amplitude = settings["waveAmplitudeMultiplier"] as? Double {
            self.waveAmplitudeMultiplier = Float(amplitude)
            Logger.shared.log("Updated waveAmplitudeMultiplier: \(amplitude)", level: .debug)
        }
        
        if let density = settings["particleDensity"] as? Double {
            self.particleDensity = Float(density)
            Logger.shared.log("Updated particleDensity: \(density)", level: .debug)
        }
        
        if let showWave = settings["showWaveLine"] as? Bool {
            self.showWaveLine = showWave
            Logger.shared.log("Updated showWaveLine: \(showWave)", level: .debug)
        }
        
        if let enableColors = settings["enableColorChanges"] as? Bool {
            self.enableColorChanges = enableColors
            Logger.shared.log("Updated enableColorChanges: \(enableColors)", level: .debug)
        }
        
        if let enableSizes = settings["enableSizeChanges"] as? Bool {
            self.enableSizeChanges = enableSizes
            Logger.shared.log("Updated enableSizeChanges: \(enableSizes)", level: .debug)
        }
        
        if let enableMove = settings["enableMovement"] as? Bool {
            self.enableMovement = enableMove
            Logger.shared.log("Updated enableMovement: \(enableMove)", level: .debug)
        }
        
        // Don't update isLoading from settings
        
        // Update colors
        if let redBase = settings["baseColorRed"] as? Double,
           let greenBase = settings["baseColorGreen"] as? Double,
           let blueBase = settings["baseColorBlue"] as? Double {
            self.baseColor = Color(NSColor(red: CGFloat(redBase), green: CGFloat(greenBase), blue: CGFloat(blueBase), alpha: 1.0))
            Logger.shared.log("Updated baseColor", level: .debug)
        }
        
        if let redAccent = settings["accentColorRed"] as? Double,
           let greenAccent = settings["accentColorGreen"] as? Double,
           let blueAccent = settings["accentColorBlue"] as? Double {
            self.accentColor = Color(NSColor(red: CGFloat(redAccent), green: CGFloat(greenAccent), blue: CGFloat(blueAccent), alpha: 1.0))
            Logger.shared.log("Updated accentColor", level: .debug)
        }
        
        // Also save to UserDefaults for future instances
        UserDefaults.standard.set(settings, forKey: "animationSettings")
        
        // Save as JSON as well
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys])
            if let jsonString = String(data: jsonData, encoding: .utf8) {
                UserDefaults.standard.set(jsonString, forKey: "animationSettingsJSON")
                Logger.shared.log("Saved JSON settings to UserDefaults", level: .debug)
            }
        } catch {
            Logger.shared.log("Failed to save JSON settings: \(error)", level: .error)
        }
        
        // Force update colors immediately
        updateParticleColors()
    }
    
    /// Draw a subtle background wave effect
    private func drawBackgroundWave(in context: GraphicsContext, size: CGSize) {
        let waveHeight = size.height * CGFloat(intensity) * 0.4 * CGFloat(waveAmplitudeMultiplier)
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
    private mutating func addEnergyBurst(in size: CGSize) {
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
    private mutating func resetParticles(in size: CGSize) {
        particles = []
        // Reset loading mode when initializing particles
        isLoading = false
        loadingPhase = 0
        
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
    private mutating func updateParticles(in size: CGSize) {
        // Check for settings updates in UserDefaults
        checkForSettingsUpdates()
        
        // Increment global animation phase using animation speed parameter
        animationPhase += 0.05 * Double(animationSpeed) * (enableMovement ? 1.0 : 0.0)
        
        // When in loading mode, increment the loading phase
        if isLoading {
            loadingPhase += 0.05 * Double(animationSpeed)
            
            // In loading mode, ensure there's only one particle
            if particles.count > 1 {
                particles = [particles.first!]
            } else if particles.isEmpty {
                particles = [createRandomParticle(nearCenter: true)]
            }
            
            // Smoothly move the particle to the center with a pulsing effect
            if let centerIndex = particles.indices.first {
                var centerParticle = particles[centerIndex]
                
                // Calculate center of view
                let centerX = size.width / 2
                let centerY = size.height / 2
                
                // Smooth movement to center
                let dx = centerX - centerParticle.position.x
                let dy = centerY - centerParticle.position.y
                let distance = sqrt(dx * dx + dy * dy)
                
                // Move toward center more quickly when further away
                let moveSpeed = min(0.1, distance * 0.05)
                
                if distance > 1.0 {
                    centerParticle.position.x += dx * moveSpeed
                    centerParticle.position.y += dy * moveSpeed
                } else {
                    // Once at center, add slight movement for visual interest
                    let jitter = sin(loadingPhase * 1.2) * 1.0
                    centerParticle.position.x = centerX + jitter
                    centerParticle.position.y = centerY + jitter * 0.5
                }
                
                // Apply pulsing effect to size if enabled
                if enableSizeChanges {
                    let pulseSize = 6.0 + (sin(loadingPhase * 2.0) + 1) * 4.0
                    centerParticle.size = pulseSize
                }
                
                // Apply color effect if enabled
                if enableColorChanges {
                    centerParticle.color = getParticleColor(intensity: 0.8, random: 0.5)
                }
                
                // Vary opacity for visual interest
                centerParticle.opacity = 0.6 + abs(sin(loadingPhase * 1.5)) * 0.4
                
                // Update the particle
                particles[centerIndex] = centerParticle
            }
            
            return // Skip normal mode updates when in loading mode
        }
        
        // Calculate wave parameters based on intensity
        let centerY = size.height / 2
        let spread = 10 + CGFloat(intensity) * (size.height * 0.3) * CGFloat(waveAmplitudeMultiplier)
        
        // Update each particle
        for i in 0..<particles.count {
            var particle = particles[i]
            
            if enableMovement {
                particle.position.x += particle.speed * CGFloat(animationSpeed)
            }
            
            // Reset position when particle goes off-screen
            if particle.position.x > size.width {
                particle.position.x = 0
                
                // Update size and speed based on current intensity and density parameter
                let densityFactor = 1.0 - (CGFloat(particleDensity) * (1.0 - CGFloat(intensity)))
                
                if enableSizeChanges {
                    particle.size = CGFloat.random(in: 3...maxParticleSize) * (0.5 + CGFloat(intensity) * 0.5) * densityFactor
                }
                
                particle.speed = 1.0 + CGFloat.random(in: 0...0.8) * CGFloat(intensity) * 2 * CGFloat(animationSpeed)
                
                if enableColorChanges {
                    particle.color = getParticleColor(intensity: intensity, random: CGFloat.random(in: 0...1))
                }
                
                particle.opacity = Double.random(in: 0.5...0.9)
            }
            
            // Vertical movement with wave pattern
            if enableMovement {
                let waveAmplitude = spread * (particle.size / maxParticleSize)
                let waveFrequency = 1.0 + (particle.size / maxParticleSize)
                let yOffset = sin(
                    (particle.phase + Double(particle.position.x) / Double(size.width) * 4 * .pi + animationPhase) * waveFrequency
                ) * Double(waveAmplitude)
                
                particle.position.y = centerY + CGFloat(yOffset)
            }
            
            // Update particle in array
            particles[i] = particle
        }
        
        // Clean up excess particles, but only in normal mode
        if particles.count > particleCount * 2 {
            particles.removeFirst(particles.count - particleCount * 2)
        }
        
        // Check if intensity has changed significantly
        if abs(intensity - lastIntensity) > 0.1 {
            updateParticleColors()
            lastIntensity = intensity
        }
    }
    
    /// Check for settings updates in UserDefaults and apply them
    private mutating func checkForSettingsUpdates() {
        // First check for JSON settings
        if let jsonString = UserDefaults.standard.string(forKey: "animationSettingsJSON"),
           let jsonData = jsonString.data(using: .utf8) {
            do {
                if let jsonSettings = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any] {
                    // Apply animation settings from JSON
                    if let value = jsonSettings["colorVariationIntensity"] as? Double {
                        colorVariationIntensity = Float(value)
                    }
                    
                    if let value = jsonSettings["animationSpeed"] as? Double {
                        animationSpeed = Float(value)
                    }
                    
                    if let value = jsonSettings["waveAmplitudeMultiplier"] as? Double {
                        waveAmplitudeMultiplier = Float(value)
                    }
                    
                    if let value = jsonSettings["particleDensity"] as? Double {
                        particleDensity = Float(value)
                    }
                    
                    if let value = jsonSettings["showWaveLine"] as? Bool {
                        showWaveLine = value
                    }
                    
                    if let value = jsonSettings["enableColorChanges"] as? Bool {
                        enableColorChanges = value
                    }
                    
                    if let value = jsonSettings["enableSizeChanges"] as? Bool {
                        enableSizeChanges = value
                    }
                    
                    if let value = jsonSettings["enableMovement"] as? Bool {
                        enableMovement = value
                    }
                    
                    // Update loading mode if present in settings
                    if let value = jsonSettings["isLoadingMode"] as? Bool, value != isLoading {
                        Logger.shared.log("Updating isLoading from JSON settings: \(value)", level: .debug)
                        setLoadingMode(value)
                    }
                    
                    // Update colors if needed
                    if let redBase = jsonSettings["baseColorRed"] as? Double,
                       let greenBase = jsonSettings["baseColorGreen"] as? Double,
                       let blueBase = jsonSettings["baseColorBlue"] as? Double {
                        baseColor = Color(NSColor(red: CGFloat(redBase), green: CGFloat(greenBase), blue: CGFloat(blueBase), alpha: 1.0))
                    }
                    
                    if let redAccent = jsonSettings["accentColorRed"] as? Double,
                       let greenAccent = jsonSettings["accentColorGreen"] as? Double,
                       let blueAccent = jsonSettings["accentColorBlue"] as? Double {
                        accentColor = Color(NSColor(red: CGFloat(redAccent), green: CGFloat(greenAccent), blue: CGFloat(blueAccent), alpha: 1.0))
                    }
                    
                    return // Skip legacy settings check if JSON was processed
                }
            } catch {
                Logger.shared.log("Failed to parse JSON settings update: \(error)", level: .error)
            }
        }
        
        // Fall back to legacy settings format
        guard let settings = UserDefaults.standard.dictionary(forKey: "animationSettings") else {
            return
        }
        
        // Apply any animation settings from UserDefaults
        if let colorVariation = settings["colorVariationIntensity"] as? Double {
            colorVariationIntensity = Float(colorVariation)
        }
        
        if let speed = settings["animationSpeed"] as? Double {
            animationSpeed = Float(speed)
        }
        
        if let amplitude = settings["waveAmplitudeMultiplier"] as? Double {
            waveAmplitudeMultiplier = Float(amplitude)
        }
        
        if let density = settings["particleDensity"] as? Double {
            particleDensity = Float(density)
        }
        
        if let showWave = settings["showWaveLine"] as? Bool {
            showWaveLine = showWave
        }
        
        if let enableColors = settings["enableColorChanges"] as? Bool {
            enableColorChanges = enableColors
        }
        
        if let enableSizes = settings["enableSizeChanges"] as? Bool {
            enableSizeChanges = enableSizes
        }
        
        if let enableMove = settings["enableMovement"] as? Bool {
            enableMovement = enableMove
        }
        
        // Don't update isLoading from settings
        
        // Update colors if needed
        if let redBase = settings["baseColorRed"] as? Double,
           let greenBase = settings["baseColorGreen"] as? Double,
           let blueBase = settings["baseColorBlue"] as? Double {
            baseColor = Color(NSColor(red: CGFloat(redBase), green: CGFloat(greenBase), blue: CGFloat(blueBase), alpha: 1.0))
        }
        
        if let redAccent = settings["accentColorRed"] as? Double,
           let greenAccent = settings["accentColorGreen"] as? Double,
           let blueAccent = settings["accentColorBlue"] as? Double {
            accentColor = Color(NSColor(red: CGFloat(redAccent), green: CGFloat(greenAccent), blue: CGFloat(blueAccent), alpha: 1.0))
        }
        
        // Update loading mode if present
        if let isLoadingValue = settings["isLoadingMode"] as? Bool, isLoadingValue != isLoading {
            Logger.shared.log("Updating isLoading from legacy settings: \(isLoadingValue)", level: .debug)
            var mutableSelf = self
            mutableSelf.setLoadingMode(isLoadingValue)
        }
    }
    
    /// Update particle colors based on the current intensity
    private mutating func updateParticleColors() {
        if !enableColorChanges { return }
        
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
        let colorVariation = Double(colorVariationIntensity)
        
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
            // Create vibrant variations based on colorVariationIntensity
            let hueVariation = (random * 0.2) - 0.1 + (energyLevel * 0.1)
            let hue = baseColor.hsbComponents.hue + hueVariation * colorVariation
            let saturation = min(1.0, baseColor.hsbComponents.saturation + (energyLevel * 0.2) * colorVariation)
            let brightness = min(1.0, baseColor.hsbComponents.brightness + (energyLevel * 0.3) * colorVariation)
            
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
    
    /// Sets the color variation intensity (0.0 to 1.0)
    func colorVariationIntensity(_ intensity: Float) -> ParticleWaveEffect {
        var copy = self
        copy.colorVariationIntensity = max(0, min(1, intensity))
        return copy
    }
    
    /// Sets the animation speed multiplier (0.5 to 2.0)
    func animationSpeed(_ speed: Float) -> ParticleWaveEffect {
        var copy = self
        copy.animationSpeed = max(0.5, min(2.0, speed))
        return copy
    }
    
    /// Sets the wave amplitude multiplier (0.5 to 2.0)
    func waveAmplitudeMultiplier(_ multiplier: Float) -> ParticleWaveEffect {
        var copy = self
        copy.waveAmplitudeMultiplier = max(0.5, min(2.0, multiplier))
        return copy
    }
    
    /// Sets the particle density distribution (0.0 to 1.0)
    func particleDensity(_ density: Float) -> ParticleWaveEffect {
        var copy = self
        copy.particleDensity = max(0, min(1, density))
        return copy
    }
    
    /// Enable or disable the background wave line
    func showWaveLine(_ enabled: Bool) -> ParticleWaveEffect {
        var copy = self
        copy.showWaveLine = enabled
        return copy
    }
    
    /// Enable or disable color changes based on intensity
    func enableColorChanges(_ enabled: Bool) -> ParticleWaveEffect {
        var copy = self
        copy.enableColorChanges = enabled
        return copy
    }
    
    /// Enable or disable size changes based on intensity
    func enableSizeChanges(_ enabled: Bool) -> ParticleWaveEffect {
        var copy = self
        copy.enableSizeChanges = enabled
        return copy
    }
    
    /// Enable or disable particle movement
    func enableMovement(_ enabled: Bool) -> ParticleWaveEffect {
        var copy = self
        copy.enableMovement = enabled
        return copy
    }
    
    /// Enable or disable loading mode
    func loadingMode(_ isLoading: Bool) -> ParticleWaveEffect {
        var copy = self
        copy.isLoading = isLoading
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

// MARK: - Loading Indicator

// Data structure for circle particles
private struct CircleParticle: Identifiable {
    let id = UUID()
    var position: CGPoint
    var size: CGFloat
    var color: Color
    var opacity: Double
    var phase: Double
}

struct LoadingIndicator: View {
    // MARK: - Properties
    @State private var rotation: Double = 0
    @State private var particles: [CircleParticle] = []
    @State private var animationPhase: Double = 0
    @StateObject private var particleState = ParticleStateManager()
    
    var baseColor: Color = .blue
    var accentColor: Color = .purple
    var particleCount: Int = 12
    var maxParticleSize: CGFloat = 8
    var circleRadius: CGFloat = 20
    
    // MARK: - Body
    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                // Draw background circle
                let centerX = size.width / 2
                let centerY = size.height / 2
                
                // Draw subtle background circle
                context.opacity = 0.2
                context.stroke(
                    Path(ellipseIn: CGRect(
                        x: centerX - circleRadius - 2,
                        y: centerY - circleRadius - 2,
                        width: (circleRadius + 2) * 2,
                        height: (circleRadius + 2) * 2
                    )),
                    with: .color(baseColor),
                    lineWidth: 1
                )
                
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
                    
                    // Add subtle glow effect
                    if particle.size > maxParticleSize * 0.7 {
                        var glowContext = context
                        glowContext.opacity = particle.opacity * 0.5
                        glowContext.blendMode = .screen
                        glowContext.fill(
                            path.strokedPath(StrokeStyle(lineWidth: 1)),
                            with: .color(particle.color)
                        )
                    }
                }
            }
            .frame(width: circleRadius * 2 + 20, height: circleRadius * 2 + 20)
            .onChange(of: timeline.date) { _, _ in
                // Call updateParticles on state
                particleState.updateParticles(
                    particles: &particles, 
                    animationPhase: &animationPhase, 
                    rotation: &rotation, 
                    particleCount: particleCount, 
                    circleRadius: circleRadius, 
                    maxParticleSize: maxParticleSize, 
                    baseColor: baseColor, 
                    accentColor: accentColor
                )
            }
            .onAppear {
                // Initialize particles on appear
                particleState.initializeParticles(
                    particles: &particles,
                    particleCount: particleCount,
                    circleRadius: circleRadius,
                    maxParticleSize: maxParticleSize,
                    baseColor: baseColor,
                    accentColor: accentColor
                )
            }
        }
    }
}

struct CircleParticleRing: View {
    // MARK: - Properties
    @State private var rotation: Double = 0
    @State private var particles: [CircleParticle] = []
    @State private var animationPhase: Double = 0
    @StateObject private var particleState = ParticleStateManager()
    
    var baseColor: Color = .blue
    var accentColor: Color = .purple
    var particleCount: Int = 12
    var maxParticleSize: CGFloat = 8
    var circleRadius: CGFloat = 20
    
    // MARK: - Body
    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                // Draw background circle
                let centerX = size.width / 2
                let centerY = size.height / 2
                
                // Draw subtle background circle
                context.opacity = 0.2
                context.stroke(
                    Path(ellipseIn: CGRect(
                        x: centerX - circleRadius - 2,
                        y: centerY - circleRadius - 2,
                        width: (circleRadius + 2) * 2,
                        height: (circleRadius + 2) * 2
                    )),
                    with: .color(baseColor),
                    lineWidth: 1
                )
                
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
                    
                    // Add subtle glow effect
                    if particle.size > maxParticleSize * 0.7 {
                        var glowContext = context
                        glowContext.opacity = particle.opacity * 0.5
                        glowContext.blendMode = .screen
                        glowContext.fill(
                            path.strokedPath(StrokeStyle(lineWidth: 1)),
                            with: .color(particle.color)
                        )
                    }
                }
            }
            .frame(width: circleRadius * 2 + 20, height: circleRadius * 2 + 20)
            .onChange(of: timeline.date) { _, _ in
                // Call updateParticles on state
                particleState.updateParticles(
                    particles: &particles, 
                    animationPhase: &animationPhase, 
                    rotation: &rotation, 
                    particleCount: particleCount, 
                    circleRadius: circleRadius, 
                    maxParticleSize: maxParticleSize, 
                    baseColor: baseColor, 
                    accentColor: accentColor
                )
            }
            .onAppear {
                // Initialize particles on appear
                particleState.initializeParticles(
                    particles: &particles,
                    particleCount: particleCount,
                    circleRadius: circleRadius,
                    maxParticleSize: maxParticleSize,
                    baseColor: baseColor,
                    accentColor: accentColor
                )
            }
        }
    }
}

// Before the CircleParticleRing struct
// State manager to handle mutating operations on particles
class ParticleStateManager: ObservableObject {
    /// Initialize particles around the circle
    fileprivate func initializeParticles(
        particles: inout [CircleParticle],
        particleCount: Int,
        circleRadius: CGFloat,
        maxParticleSize: CGFloat,
        baseColor: Color,
        accentColor: Color
    ) {
        particles = []
        
        // Create particles distributed evenly around a circle
        for i in 0..<particleCount {
            let angle = (Double(i) / Double(particleCount)) * 2 * .pi
            let x = cos(angle) * Double(circleRadius) + 20 + circleRadius
            let y = sin(angle) * Double(circleRadius) + 20 + circleRadius
            
            // Vary particle size slightly
            let size = CGFloat.random(in: maxParticleSize * 0.5...maxParticleSize)
            
            // Create color based on position in the circle
            let colorMix = Double(i) / Double(particleCount)
            let particleColor = getParticleColor(colorMix: colorMix, baseColor: baseColor, accentColor: accentColor)
            
            particles.append(CircleParticle(
                position: CGPoint(x: x, y: y),
                size: size,
                color: particleColor,
                opacity: Double.random(in: 0.6...0.9),
                phase: Double(i) / Double(particleCount) * 2 * .pi
            ))
        }
    }
    
    /// Update particle properties for animation
    fileprivate func updateParticles(
        particles: inout [CircleParticle],
        animationPhase: inout Double,
        rotation: inout Double,
        particleCount: Int,
        circleRadius: CGFloat,
        maxParticleSize: CGFloat,
        baseColor: Color,
        accentColor: Color
    ) {
        // Increment global animation phase
        animationPhase += 0.03
        rotation += 0.01
        
        // Update each particle
        for i in 0..<particles.count {
            var particle = particles[i]
            
            // Calculate angle based on original position plus rotation
            let baseAngle = (Double(i) / Double(particleCount)) * 2 * .pi
            let angle = baseAngle + rotation
            
            // Calculate new position
            let centerX = 20 + Double(circleRadius)
            let centerY = 20 + Double(circleRadius)
            let x = cos(angle) * Double(circleRadius) + centerX
            let y = sin(angle) * Double(circleRadius) + centerY
            
            // Update position
            particle.position = CGPoint(x: x, y: y)
            
            // Pulse size based on phase
            let pulseFactor = 0.7 + abs(sin(particle.phase + animationPhase)) * 0.5
            particle.size = maxParticleSize * CGFloat(pulseFactor)
            
            // Pulse opacity slightly
            particle.opacity = 0.6 + abs(sin(particle.phase + animationPhase * 0.8)) * 0.4
            
            // Gradually shift colors
            let colorMix = (Double(i) / Double(particleCount) + animationPhase * 0.05).truncatingRemainder(dividingBy: 1.0)
            particle.color = getParticleColor(colorMix: colorMix, baseColor: baseColor, accentColor: accentColor)
            
            // Update particle in array
            particles[i] = particle
        }
    }
    
    /// Get a color for a particle based on position in circle
    private func getParticleColor(colorMix: Double, baseColor: Color, accentColor: Color) -> Color {
        // Use a similar color scheme to ParticleWaveEffect
        if colorMix < 0.5 {
            // Map 0...0.5 to 0...1 for interpolation from base to accent
            let normalizedMix = colorMix * 2
            return Color.interpolateRGB(
                from: baseColor,
                to: accentColor,
                amount: normalizedMix
            )
        } else {
            // Map 0.5...1 to 1...0 for interpolation from accent back to base
            let normalizedMix = (colorMix - 0.5) * 2
            return Color.interpolateRGB(
                from: accentColor,
                to: baseColor,
                amount: normalizedMix
            )
        }
    }
}

// Extension for color interpolation 
extension Color {
    static func interpolateRGB(from color1: Color, to color2: Color, amount: Double) -> Color {
        let amount = max(0, min(1, amount)) // clamp to 0...1
        
        // Convert colors to NSColor for component access
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