import SwiftUI

class AnimationDebugViewModel: ObservableObject {
    // The only two properties we need
    @Published var previewIntensity: Float = 0.5
    @Published var isLoadingMode: Bool = false
} 