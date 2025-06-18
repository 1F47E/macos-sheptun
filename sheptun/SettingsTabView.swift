import SwiftUI

struct SettingsTabView: View {
    @State private var selectedTab = "provider"
    
    var body: some View {
        VStack(spacing: 0) {
            customTabBar
            
            tabContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(NSColor.controlBackgroundColor))
        }
    }
    
    private var customTabBar: some View {
        HStack(spacing: 0) {
            TabButton(
                title: "Provider",
                icon: "network",
                isSelected: selectedTab == "provider",
                action: { selectedTab = "provider" }
            )
            
            TabButton(
                title: "Audio",
                icon: "waveform",
                isSelected: selectedTab == "audio",
                action: { selectedTab = "audio" }
            )
            
            TabButton(
                title: "Recording",
                icon: "record.circle",
                isSelected: selectedTab == "recording",
                action: { selectedTab = "recording" }
            )
            
            TabButton(
                title: "History",
                icon: "clock.arrow.circlepath",
                isSelected: selectedTab == "history",
                action: { selectedTab = "history" }
            )
            
            // About tab hidden as requested
            // TabButton(
            //     title: "About",
            //     icon: "info.circle",
            //     isSelected: selectedTab == "about",
            //     action: { selectedTab = "about" }
            // )
        }
        .background(Color(NSColor.windowBackgroundColor))
        .overlay(
            Divider()
                .frame(height: 1)
                .background(Color(NSColor.separatorColor)),
            alignment: .bottom
        )
    }
    
    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case "provider":
            ProviderSettingsView()
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .move(edge: .leading).combined(with: .opacity)
                ))
        case "audio":
            AudioSettingsView()
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .move(edge: .leading).combined(with: .opacity)
                ))
        case "recording":
            RecordingSettingsView()
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .move(edge: .leading).combined(with: .opacity)
                ))
        case "history":
            HistoryView()
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .move(edge: .leading).combined(with: .opacity)
                ))
        case "about":
            AboutView()
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .move(edge: .leading).combined(with: .opacity)
                ))
        default:
            ProviderSettingsView()
        }
    }
}

struct TabButton: View {
    let title: String
    let icon: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 22))
                    .symbolVariant(isSelected ? .fill : .none)
                
                Text(title)
                    .font(.caption)
            }
            .foregroundColor(isSelected ? Color.accentColor : Color.secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .padding(.horizontal, 8)
            .contentShape(Rectangle()) // Makes entire area clickable
            .background(
                VStack(spacing: 0) {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.accentColor.opacity(0.1))
                    }
                    Spacer()
                }
            )
            .overlay(
                Rectangle()
                    .fill(isSelected ? Color.accentColor : Color.clear)
                    .frame(height: 2),
                alignment: .bottom
            )
        }
        .buttonStyle(PlainButtonStyle())
        .animation(.easeInOut(duration: 0.2), value: isSelected)
    }
}

#Preview {
    SettingsTabView()
        .frame(width: 600, height: 500)
}