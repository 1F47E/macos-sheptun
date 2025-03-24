import SwiftUI

struct AnimationDebugView: View {
    @StateObject private var viewModel = AnimationDebugViewModel()
    
    var body: some View {
        VStack(spacing: 0) {
            headerView
            
            Divider()
            
            ScrollView {
                VStack(spacing: 20) {
                    audioVisualizationView
                    
                    animationControlsView
                    
                    jsonSettingsView
                    
                    saveLoadView
                }
                .padding()
            }
        }
        .frame(minWidth: 550, minHeight: 450)
        .background(Color(.windowBackgroundColor))
        .onAppear {
            viewModel.loadSavedSettings()
            viewModel.applyCurrentSettings()
        }
    }
    
    // Header with title
    private var headerView: some View {
        HStack {
            Text("Animation Debug")
                .font(.system(size: 22, weight: .semibold))
            
            Spacer()
        }
        .padding()
    }
    
    // Audio visualization preview
    private var audioVisualizationView: some View {
        VStack(spacing: 10) {
            HStack {
                Text("Preview:")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Slider(value: $viewModel.previewIntensity, in: 0.0...1.0, step: 0.05)
                    .frame(width: 200)
                
                Text(String(format: "%.2f", viewModel.previewIntensity))
                    .monospacedDigit()
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
                    .frame(width: 40, alignment: .trailing)
            }
            
            ParticleWaveEffect(intensity: viewModel.previewIntensity)
                .baseColor(viewModel.baseColor)
                .accentColor(viewModel.accentColor)
                .height(60)
                .colorVariationIntensity(viewModel.colorVariationIntensity)
                .animationSpeed(viewModel.animationSpeed)
                .waveAmplitudeMultiplier(viewModel.waveAmplitudeMultiplier)
                .particleDensity(viewModel.particleDensity)
                .showWaveLine(viewModel.showWaveLine)
                .enableColorChanges(viewModel.enableColorChanges)
                .enableSizeChanges(viewModel.enableSizeChanges)
                .enableMovement(viewModel.enableMovement)
                .loadingMode(viewModel.isLoadingMode)
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                )
        }
        .padding()
        .background(Color(.windowBackgroundColor).opacity(0.6))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.secondary.opacity(0.1), lineWidth: 1)
        )
    }
    
    // JSON Settings View
    private var jsonSettingsView: some View {
        VStack(spacing: 10) {
            HStack {
                Text("JSON Settings:")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Button("Copy to Clipboard") {
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.setString(viewModel.jsonSettingsString, forType: .string)
                }
                .font(.system(size: 12))
            }
            
            ScrollView {
                Text(viewModel.jsonSettingsString)
                    .font(.system(size: 12, design: .monospaced))
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: 150)
            .background(Color(.textBackgroundColor))
            .cornerRadius(6)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
            )
        }
        .padding()
        .background(Color(.windowBackgroundColor).opacity(0.6))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.secondary.opacity(0.1), lineWidth: 1)
        )
        .onChange(of: viewModel.baseColor) { _ in viewModel.updateJsonSettings() }
        .onChange(of: viewModel.accentColor) { _ in viewModel.updateJsonSettings() }
        .onChange(of: viewModel.colorVariationIntensity) { _ in viewModel.updateJsonSettings() }
        .onChange(of: viewModel.animationSpeed) { _ in viewModel.updateJsonSettings() }
        .onChange(of: viewModel.waveAmplitudeMultiplier) { _ in viewModel.updateJsonSettings() }
        .onChange(of: viewModel.particleDensity) { _ in viewModel.updateJsonSettings() }
        .onChange(of: viewModel.showWaveLine) { _ in viewModel.updateJsonSettings() }
        .onChange(of: viewModel.enableColorChanges) { _ in viewModel.updateJsonSettings() }
        .onChange(of: viewModel.enableSizeChanges) { _ in viewModel.updateJsonSettings() }
        .onChange(of: viewModel.enableMovement) { _ in viewModel.updateJsonSettings() }
    }
    
    // Animation controls view
    private var animationControlsView: some View {
        VStack(spacing: 12) {
            // Toggle controls for animation features
            VStack(spacing: 8) {
                HStack {
                    Text("Animation Features:")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.secondary)
                    
                    Spacer()
                }
                
                // Feature toggles in a grid layout
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    Toggle("Show Wave Line", isOn: $viewModel.showWaveLine)
                        .toggleStyle(.switch)
                        .controlSize(.small)
                    
                    Toggle("Color Changes", isOn: $viewModel.enableColorChanges)
                        .toggleStyle(.switch)
                        .controlSize(.small)
                    
                    Toggle("Size Changes", isOn: $viewModel.enableSizeChanges)
                        .toggleStyle(.switch)
                        .controlSize(.small)
                    
                    Toggle("Movement", isOn: $viewModel.enableMovement)
                        .toggleStyle(.switch)
                        .controlSize(.small)
                }
                .font(.system(size: 12))
            }
            .padding(.bottom, 4)
            
            // Loading mode button
            HStack {
                Text("Loading Mode:")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Toggle("", isOn: $viewModel.isLoadingMode)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .onChange(of: viewModel.isLoadingMode) { _, newValue in
                        viewModel.updateJsonSettings()
                        viewModel.applyCurrentSettings()
                    }
            }
            .padding(.bottom, 8)
            
            // Color selector
            VStack(spacing: 8) {
                HStack {
                    Text("Colors:")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.secondary)
                    
                    Spacer()
                }
                
                HStack(spacing: 16) {
                    VStack {
                        Text("Base Color")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                        
                        ColorPicker("", selection: $viewModel.baseColor)
                            .labelsHidden()
                    }
                    
                    VStack {
                        Text("Accent Color")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                        
                        ColorPicker("", selection: $viewModel.accentColor)
                            .labelsHidden()
                    }
                    
                    Spacer()
                }
            }
            .padding(.vertical, 8)
            
            Divider()
                .padding(.vertical, 4)
            
            // Slider controls
            VStack(spacing: 12) {
                parameterSlider(
                    title: "Color Variation:",
                    value: $viewModel.colorVariationIntensity,
                    range: 0.0...1.0,
                    step: 0.1,
                    color: .blue
                )
                
                parameterSlider(
                    title: "Animation Speed:",
                    value: $viewModel.animationSpeed,
                    range: 0.5...2.0,
                    step: 0.1,
                    color: .green
                )
                
                parameterSlider(
                    title: "Wave Amplitude:",
                    value: $viewModel.waveAmplitudeMultiplier,
                    range: 0.5...2.0,
                    step: 0.1,
                    color: .purple
                )
                
                parameterSlider(
                    title: "Particle Density:",
                    value: $viewModel.particleDensity,
                    range: 0.0...1.0,
                    step: 0.1,
                    color: .orange
                )
            }
            
            HStack {
                Spacer()
                
                Button("Apply Settings") {
                    viewModel.applyCurrentSettings()
                }
                .font(.system(size: 12, weight: .medium))
                .buttonStyle(.plain)
                .foregroundColor(.green)
                .padding(.trailing, 8)
                
                Button("Reset to Default") {
                    viewModel.resetAnimationParameters()
                }
                .font(.system(size: 12, weight: .medium))
                .buttonStyle(.plain)
                .foregroundColor(.blue)
            }
            .padding(.top, 4)
        }
        .padding()
        .background(Color(.windowBackgroundColor).opacity(0.6))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.secondary.opacity(0.1), lineWidth: 1)
        )
    }
    
    // Save/Load settings view
    private var saveLoadView: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Saved Presets:")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.secondary)
                
                Spacer()
            }
            
            if viewModel.savedPresets.isEmpty {
                Text("No saved presets yet")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .padding()
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(viewModel.savedPresets, id: \.name) { preset in
                            Button(action: {
                                viewModel.loadPreset(preset)
                            }) {
                                Text(preset.name)
                                    .font(.system(size: 13))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(Color.blue.opacity(0.1))
                                    .cornerRadius(8)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 2)
                }
                .frame(height: 40)
            }
            
            HStack {
                TextField("Preset name", text: $viewModel.presetName)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .frame(width: 200)
                
                Button("Save Settings") {
                    viewModel.saveCurrentSettings()
                }
                .disabled(viewModel.presetName.isEmpty)
                
                Spacer()
            }
        }
        .padding()
        .background(Color(.windowBackgroundColor).opacity(0.6))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.secondary.opacity(0.1), lineWidth: 1)
        )
    }
    
    // Helper function to create consistent parameter sliders
    private func parameterSlider(
        title: String,
        value: Binding<Float>,
        range: ClosedRange<Float>,
        step: Float,
        color: Color
    ) -> some View {
        VStack(spacing: 4) {
            HStack {
                Text(title)
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Text(String(format: "%.1f", value.wrappedValue))
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundColor(.secondary)
            }
            
            Slider(value: value, in: range, step: step)
                .accentColor(color)
        }
    }
}

// Preview
struct AnimationDebugView_Previews: PreviewProvider {
    static var previews: some View {
        AnimationDebugView()
    }
} 