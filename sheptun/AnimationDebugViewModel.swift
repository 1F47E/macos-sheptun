import SwiftUI

// Helper extension to safely get RGB components from a Color
private extension Color {
    var rgbComponents: (red: Double, green: Double, blue: Double) {
        let nsColor = NSColor(self)
        guard let colorSpace = nsColor.usingColorSpace(.sRGB) else {
            return (0, 0, 0)
        }
        
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        
        colorSpace.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        return (Double(red), Double(green), Double(blue))
    }
}

class AnimationDebugViewModel: ObservableObject {
    // Animation parameters
    @Published var baseColor: Color = .blue
    @Published var accentColor: Color = .indigo
    @Published var colorVariationIntensity: Float = 1.0
    @Published var animationSpeed: Float = 1.0
    @Published var waveAmplitudeMultiplier: Float = 1.0
    @Published var particleDensity: Float = 0.5
    @Published var showWaveLine: Bool = true
    @Published var enableColorChanges: Bool = true
    @Published var enableSizeChanges: Bool = true
    @Published var enableMovement: Bool = true
    @Published var isLoadingMode: Bool = false
    
    // Preview control
    @Published var previewIntensity: Float = 0.5
    
    // JSON output
    @Published var jsonSettingsString: String = ""
    
    // Save/load functionality
    @Published var presetName: String = ""
    @Published var savedPresets: [AnimationPreset] = []
    
    // Logger
    private let logger = Logger.shared
    
    // Default parameters for reset
    private let defaultBaseColor: Color = .blue
    private let defaultAccentColor: Color = .indigo
    private let defaultColorVariation: Float = 1.0
    private let defaultAnimationSpeed: Float = 1.0
    private let defaultWaveAmplitude: Float = 1.0
    private let defaultParticleDensity: Float = 0.5
    private let defaultShowWaveLine: Bool = true
    private let defaultEnableColorChanges: Bool = true
    private let defaultEnableSizeChanges: Bool = true
    private let defaultEnableMovement: Bool = true
    private let defaultIsLoadingMode: Bool = false
    
    init() {
        loadSavedSettings()
        loadDefaultAnimationSettings()
        updateJsonSettings()
    }
    
    private func loadDefaultAnimationSettings() {
        // Try to load default animation settings from UserDefaults
        if let data = UserDefaults.standard.data(forKey: "animationPresets"),
           let presets = try? JSONDecoder().decode([AnimationPresetCodable].self, from: data),
           let defaultPreset = presets.first {
            
            // Use the first preset as default
            logger.log("Loading default animation settings from saved preset: \(defaultPreset.name)", level: .info)
            
            baseColor = Color(
                red: defaultPreset.baseColorRed,
                green: defaultPreset.baseColorGreen,
                blue: defaultPreset.baseColorBlue
            )
            accentColor = Color(
                red: defaultPreset.accentColorRed,
                green: defaultPreset.accentColorGreen,
                blue: defaultPreset.accentColorBlue
            )
            colorVariationIntensity = defaultPreset.colorVariationIntensity
            animationSpeed = defaultPreset.animationSpeed
            waveAmplitudeMultiplier = defaultPreset.waveAmplitudeMultiplier
            particleDensity = defaultPreset.particleDensity
            showWaveLine = defaultPreset.showWaveLine
            enableColorChanges = defaultPreset.enableColorChanges
            enableSizeChanges = defaultPreset.enableSizeChanges
            enableMovement = defaultPreset.enableMovement
            
            // Apply these settings to be used by the ParticleWaveEffect
            applyCurrentSettings()
        }
    }
    
    func resetAnimationParameters() {
        baseColor = defaultBaseColor
        accentColor = defaultAccentColor
        colorVariationIntensity = defaultColorVariation
        animationSpeed = defaultAnimationSpeed
        waveAmplitudeMultiplier = defaultWaveAmplitude
        particleDensity = defaultParticleDensity
        showWaveLine = defaultShowWaveLine
        enableColorChanges = defaultEnableColorChanges
        enableSizeChanges = defaultEnableSizeChanges
        enableMovement = defaultEnableMovement
        isLoadingMode = defaultIsLoadingMode
        
        // Apply the changes
        applyCurrentSettings()
    }
    
    func updateJsonSettings() {
        // Convert Color to RGB components for JSON
        let baseComponents = baseColor.rgbComponents
        let accentComponents = accentColor.rgbComponents
        
        // Create settings dictionary
        let settings: [String: Any] = [
            "baseColorRed": baseComponents.red,
            "baseColorGreen": baseComponents.green,
            "baseColorBlue": baseComponents.blue,
            "accentColorRed": accentComponents.red,
            "accentColorGreen": accentComponents.green,
            "accentColorBlue": accentComponents.blue,
            "colorVariationIntensity": Double(colorVariationIntensity),
            "animationSpeed": Double(animationSpeed),
            "waveAmplitudeMultiplier": Double(waveAmplitudeMultiplier),
            "particleDensity": Double(particleDensity),
            "showWaveLine": showWaveLine,
            "enableColorChanges": enableColorChanges,
            "enableSizeChanges": enableSizeChanges,
            "enableMovement": enableMovement,
            "isLoadingMode": isLoadingMode
        ]
        
        // Convert to JSON
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys])
            if let jsonString = String(data: jsonData, encoding: .utf8) {
                jsonSettingsString = jsonString
                
                // Save JSON to UserDefaults
                UserDefaults.standard.set(jsonString, forKey: "animationSettingsJSON")
                logger.log("Saved JSON animation settings to UserDefaults", level: .debug)
            }
        } catch {
            logger.log("Failed to generate JSON settings: \(error)", level: .error)
        }
    }
    
    func applyCurrentSettings() {
        logger.log("Applying current animation settings", level: .info)
        
        // Convert Color to RGB components for storage
        let baseComponents = baseColor.rgbComponents
        let accentComponents = accentColor.rgbComponents
        
        // Create settings dictionary
        let settings: [String: Any] = [
            "baseColorRed": baseComponents.red,
            "baseColorGreen": baseComponents.green,
            "baseColorBlue": baseComponents.blue,
            "accentColorRed": accentComponents.red,
            "accentColorGreen": accentComponents.green,
            "accentColorBlue": accentComponents.blue,
            "colorVariationIntensity": Double(colorVariationIntensity),
            "animationSpeed": Double(animationSpeed),
            "waveAmplitudeMultiplier": Double(waveAmplitudeMultiplier),
            "particleDensity": Double(particleDensity),
            "showWaveLine": showWaveLine,
            "enableColorChanges": enableColorChanges,
            "enableSizeChanges": enableSizeChanges,
            "enableMovement": enableMovement,
            "isLoadingMode": isLoadingMode
        ]
        
        // Log the loading mode state for debugging
        logger.log("Setting isLoadingMode to: \(isLoadingMode)", level: .debug)
        
        // Save to UserDefaults
        UserDefaults.standard.set(settings, forKey: "animationSettings")
        logger.log("Saved animation settings to UserDefaults", level: .info)
        
        // Update JSON string
        updateJsonSettings()
        
        // Post notification to update any existing ParticleWaveEffect instances
        NotificationCenter.default.post(
            name: NSNotification.Name("AnimationSettingsChanged"),
            object: nil,
            userInfo: settings
        )
        logger.log("Posted AnimationSettingsChanged notification with isLoadingMode: \(isLoadingMode)", level: .info)
    }
    
    func saveCurrentSettings() {
        guard !presetName.isEmpty else { return }
        
        // Create a new preset
        let preset = AnimationPreset(
            name: presetName,
            baseColor: baseColor,
            accentColor: accentColor,
            colorVariationIntensity: colorVariationIntensity,
            animationSpeed: animationSpeed,
            waveAmplitudeMultiplier: waveAmplitudeMultiplier,
            particleDensity: particleDensity,
            showWaveLine: showWaveLine,
            enableColorChanges: enableColorChanges,
            enableSizeChanges: enableSizeChanges,
            enableMovement: enableMovement
        )
        
        // Remove existing preset with the same name
        savedPresets.removeAll(where: { $0.name == presetName })
        
        // Add the new preset
        savedPresets.append(preset)
        
        // Save to UserDefaults
        savePresetsToUserDefaults()
        
        // Apply the current settings
        applyCurrentSettings()
        
        // Clear the preset name field
        presetName = ""
        
        logger.log("Saved animation preset: \(preset.name)", level: .info)
    }
    
    func loadPreset(_ preset: AnimationPreset) {
        baseColor = preset.baseColor
        accentColor = preset.accentColor
        colorVariationIntensity = preset.colorVariationIntensity
        animationSpeed = preset.animationSpeed
        waveAmplitudeMultiplier = preset.waveAmplitudeMultiplier
        particleDensity = preset.particleDensity
        showWaveLine = preset.showWaveLine
        enableColorChanges = preset.enableColorChanges
        enableSizeChanges = preset.enableSizeChanges
        enableMovement = preset.enableMovement
        
        // Apply the loaded settings immediately
        applyCurrentSettings()
        
        logger.log("Loaded animation preset: \(preset.name)", level: .info)
    }
    
    func loadSavedSettings() {
        // Try loading from JSON format first
        if let jsonString = UserDefaults.standard.string(forKey: "animationSettingsJSON"),
           let jsonData = jsonString.data(using: .utf8) {
            do {
                if let jsonSettings = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any] {
                    // Apply JSON settings
                    if let baseColorRed = jsonSettings["baseColorRed"] as? Double,
                       let baseColorGreen = jsonSettings["baseColorGreen"] as? Double,
                       let baseColorBlue = jsonSettings["baseColorBlue"] as? Double {
                        baseColor = Color(red: baseColorRed, green: baseColorGreen, blue: baseColorBlue)
                    }
                    
                    if let accentColorRed = jsonSettings["accentColorRed"] as? Double,
                       let accentColorGreen = jsonSettings["accentColorGreen"] as? Double,
                       let accentColorBlue = jsonSettings["accentColorBlue"] as? Double {
                        accentColor = Color(red: accentColorRed, green: accentColorGreen, blue: accentColorBlue)
                    }
                    
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
                    
                    if let value = jsonSettings["isLoadingMode"] as? Bool {
                        isLoadingMode = value
                    }
                    
                    // Set JSON string
                    jsonSettingsString = jsonString
                    
                    logger.log("Loaded animation settings from JSON", level: .info)
                }
            } catch {
                logger.log("Failed to parse JSON animation settings: \(error)", level: .error)
            }
        }
        
        // Load presets from UserDefaults
        if let data = UserDefaults.standard.data(forKey: "animationPresets") {
            do {
                let decoder = JSONDecoder()
                let colorCodablePresets = try decoder.decode([AnimationPresetCodable].self, from: data)
                
                // Convert ColorCodable to Color
                savedPresets = colorCodablePresets.map { preset in
                    AnimationPreset(
                        name: preset.name,
                        baseColor: Color(
                            red: preset.baseColorRed,
                            green: preset.baseColorGreen,
                            blue: preset.baseColorBlue
                        ),
                        accentColor: Color(
                            red: preset.accentColorRed,
                            green: preset.accentColorGreen,
                            blue: preset.accentColorBlue
                        ),
                        colorVariationIntensity: preset.colorVariationIntensity,
                        animationSpeed: preset.animationSpeed,
                        waveAmplitudeMultiplier: preset.waveAmplitudeMultiplier,
                        particleDensity: preset.particleDensity,
                        showWaveLine: preset.showWaveLine,
                        enableColorChanges: preset.enableColorChanges,
                        enableSizeChanges: preset.enableSizeChanges,
                        enableMovement: preset.enableMovement
                    )
                }
                
                logger.log("Loaded \(savedPresets.count) animation presets", level: .info)
            } catch {
                logger.log("Failed to decode animation presets: \(error)", level: .error)
            }
        }
    }
    
    private func savePresetsToUserDefaults() {
        // Convert to codable type
        let codablePresets = savedPresets.map { preset -> AnimationPresetCodable in
            // Convert Color to RGB components
            let nsBaseColor = NSColor(preset.baseColor)
            let nsAccentColor = NSColor(preset.accentColor)
            
            return AnimationPresetCodable(
                name: preset.name,
                baseColorRed: Double(nsBaseColor.redComponent),
                baseColorGreen: Double(nsBaseColor.greenComponent),
                baseColorBlue: Double(nsBaseColor.blueComponent),
                accentColorRed: Double(nsAccentColor.redComponent),
                accentColorGreen: Double(nsAccentColor.greenComponent),
                accentColorBlue: Double(nsAccentColor.blueComponent),
                colorVariationIntensity: preset.colorVariationIntensity,
                animationSpeed: preset.animationSpeed,
                waveAmplitudeMultiplier: preset.waveAmplitudeMultiplier,
                particleDensity: preset.particleDensity,
                showWaveLine: preset.showWaveLine,
                enableColorChanges: preset.enableColorChanges,
                enableSizeChanges: preset.enableSizeChanges,
                enableMovement: preset.enableMovement
            )
        }
        
        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(codablePresets)
            UserDefaults.standard.set(data, forKey: "animationPresets")
            logger.log("Saved \(codablePresets.count) animation presets to UserDefaults", level: .info)
        } catch {
            logger.log("Failed to encode animation presets: \(error)", level: .error)
        }
    }
}

// Struct to represent an animation preset
struct AnimationPreset {
    let name: String
    let baseColor: Color
    let accentColor: Color
    let colorVariationIntensity: Float
    let animationSpeed: Float
    let waveAmplitudeMultiplier: Float
    let particleDensity: Float
    let showWaveLine: Bool
    let enableColorChanges: Bool
    let enableSizeChanges: Bool
    let enableMovement: Bool
}

// Codable version of the preset for storage
struct AnimationPresetCodable: Codable {
    let name: String
    let baseColorRed: Double
    let baseColorGreen: Double
    let baseColorBlue: Double
    let accentColorRed: Double
    let accentColorGreen: Double
    let accentColorBlue: Double
    let colorVariationIntensity: Float
    let animationSpeed: Float
    let waveAmplitudeMultiplier: Float
    let particleDensity: Float
    let showWaveLine: Bool
    let enableColorChanges: Bool
    let enableSizeChanges: Bool
    let enableMovement: Bool
} 