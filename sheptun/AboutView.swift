import SwiftUI

struct AboutView: View {
    @State private var appVersion: String = ""
    @State private var buildNumber: String = ""
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                appInfoSection
                
                featuresSection
                
                supportSection
                
                creditsSection
            }
            .padding(24)
        }
        .onAppear {
            loadVersionInfo()
        }
    }
    
    private var appInfoSection: some View {
        VStack(spacing: 16) {
            Image(systemName: "waveform.circle.fill")
                .font(.system(size: 80))
                .foregroundColor(.accentColor)
                .symbolRenderingMode(.hierarchical)
            
            Text("Sheptun")
                .font(.largeTitle)
                .fontWeight(.bold)
            
            Text("Speech to Text for macOS")
                .font(.title3)
                .foregroundColor(.secondary)
            
            HStack {
                Label("Version \(appVersion)", systemImage: "tag")
                if !buildNumber.isEmpty {
                    Text("(\(buildNumber))")
                        .foregroundColor(.secondary)
                }
            }
            .font(.caption)
        }
    }
    
    private var featuresSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Features")
                .font(.headline)
            
            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    FeatureRow(
                        icon: "mic.circle",
                        title: "Global Hotkey Recording",
                        description: "Record from anywhere with a customizable hotkey"
                    )
                    
                    Divider()
                    
                    FeatureRow(
                        icon: "network",
                        title: "Multiple AI Providers",
                        description: "Choose between OpenAI, Groq, and Deepgram"
                    )
                    
                    Divider()
                    
                    FeatureRow(
                        icon: "doc.on.clipboard",
                        title: "Auto-Paste",
                        description: "Automatically paste transcribed text"
                    )
                    
                    Divider()
                    
                    FeatureRow(
                        icon: "clock.arrow.circlepath",
                        title: "History Tracking",
                        description: "All transcriptions are saved to local database"
                    )
                }
                .padding()
            }
        }
    }
    
    private var supportSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Support")
                .font(.headline)
            
            GroupBox {
                VStack(spacing: 12) {
                    LinkRow(
                        icon: "questionmark.circle",
                        title: "Documentation",
                        subtitle: "Learn how to use Sheptun",
                        url: "https://github.com/your-repo/sheptun/wiki"
                    )
                    
                    Divider()
                    
                    LinkRow(
                        icon: "exclamationmark.bubble",
                        title: "Report an Issue",
                        subtitle: "Found a bug? Let us know",
                        url: "https://github.com/your-repo/sheptun/issues"
                    )
                    
                    Divider()
                    
                    LinkRow(
                        icon: "envelope",
                        title: "Contact Developer",
                        subtitle: "Get in touch via email",
                        url: "mailto:support@sheptun.app"
                    )
                }
                .padding()
            }
        }
    }
    
    private var creditsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Credits")
                .font(.headline)
            
            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Created by")
                            .foregroundColor(.secondary)
                        Text("kass")
                            .fontWeight(.medium)
                    }
                    
                    Divider()
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Built with")
                            .foregroundColor(.secondary)
                        
                        HStack(spacing: 12) {
                            TechBadge(name: "SwiftUI", color: .blue)
                            TechBadge(name: "AVFoundation", color: .orange)
                            TechBadge(name: "GRDB", color: .green)
                        }
                    }
                    
                    Divider()
                    
                    HStack {
                        Text("License")
                            .foregroundColor(.secondary)
                        Text("MIT")
                            .fontWeight(.medium)
                    }
                }
                .padding()
            }
        }
    }
    
    private func loadVersionInfo() {
        if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
            appVersion = version
        } else {
            appVersion = "1.0.0"
        }
        
        if let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String {
            buildNumber = build
        }
    }
}

struct FeatureRow: View {
    let icon: String
    let title: String
    let description: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(.accentColor)
                .frame(width: 30)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
    }
}

struct LinkRow: View {
    let icon: String
    let title: String
    let subtitle: String
    let url: String
    
    var body: some View {
        Button(action: openURL) {
            HStack {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(.accentColor)
                    .frame(width: 30)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                    
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Image(systemName: "arrow.up.right.square")
                    .foregroundColor(.secondary)
            }
        }
        .buttonStyle(.plain)
        .onHover { isHovering in
            if isHovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
    }
    
    private func openURL() {
        if let url = URL(string: url) {
            NSWorkspace.shared.open(url)
        }
    }
}

struct TechBadge: View {
    let name: String
    let color: Color
    
    var body: some View {
        Text(name)
            .font(.caption)
            .fontWeight(.medium)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.2))
            .foregroundColor(color)
            .cornerRadius(4)
    }
}

#Preview {
    AboutView()
        .frame(width: 600, height: 500)
}