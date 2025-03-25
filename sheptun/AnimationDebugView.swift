import SwiftUI

struct AnimationDebugView: View {
    @StateObject private var viewModel = AnimationDebugViewModel()
    
    var body: some View {
        VStack(spacing: 0) {
            headerView
            
            Divider()
            
            VStack(spacing: 20) {
                audioVisualizationView
                
                modeToggleView
            }
            .padding()
        }
        .frame(minWidth: 450, minHeight: 250)
        .background(Color(.windowBackgroundColor))
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
                .loadingMode(viewModel.isLoadingMode)
                .frame(height: 80)
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
    
    // Mode toggle view
    private var modeToggleView: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Animation Mode:")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.secondary)
                
                Spacer()
            }
            
            HStack(spacing: 20) {
                Toggle("Loading Mode", isOn: $viewModel.isLoadingMode)
                    .toggleStyle(.switch)
                
                Spacer()
            }
            
            Text(viewModel.isLoadingMode ? "Loading mode: Circular animation suitable for loading states" : "Voice recording mode: Wave animation that responds to audio intensity")
                .font(.system(size: 13))
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 8)
        }
        .padding()
        .background(Color(.windowBackgroundColor).opacity(0.6))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.secondary.opacity(0.1), lineWidth: 1)
        )
    }
}

// Preview
struct AnimationDebugView_Previews: PreviewProvider {
    static var previews: some View {
        AnimationDebugView()
    }
} 