//
//  sheptunApp.swift
//  sheptun
//
//  Created by kass on 22/03/25.
//

import SwiftUI
import AppKit

@main
struct sheptunApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    private let settings = SettingsManager.shared
    private let logger = Logger.shared
    private var settingsWindow: NSWindow?
    private let hotkeyManager = HotkeyManager.shared
    private var hasMicrophones: Bool = false
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        logger.log("Application did finish launching", level: .info)
        
        // Hide dock icon
        NSApp.setActivationPolicy(.accessory)
        
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        // Check for available microphones
        checkForAvailableMicrophones()
        
        if let button = statusItem.button {
            let iconName = hasMicrophones ? "waveform" : "waveform"
            let iconColor = hasMicrophones ? NSColor.controlAccentColor : NSColor.red
            
            let image = NSImage(systemSymbolName: iconName, accessibilityDescription: "Sheptun")?.tinted(with: iconColor)
            button.image = image
            logger.log("Status bar button created with \(hasMicrophones ? "normal" : "red") waveform icon")
        } else {
            logger.log("Failed to create status bar button", level: .error)
        }
        
        setupMenu()
        registerHotkey()
        
        // Debug output for the API key
        if !settings.openAIKey.isEmpty {
            logger.log("App started with API key: \(settings.maskAPIKey(settings.openAIKey))")
            print("App started with API key: \(settings.maskAPIKey(settings.openAIKey))")
        } else {
            logger.log("App started with no API key set", level: .warning)
            print("App started with no API key set")
        }
        
        // Check microphone permission on app launch
        checkMicrophonePermission()
    }
    
    // Check if any microphones are available
    private func checkForAvailableMicrophones() {
        let availableMics = settings.getAvailableMicrophones()
        hasMicrophones = !availableMics.isEmpty
        
        if !hasMicrophones {
            logger.log("No microphones found on system", level: .warning)
        } else {
            logger.log("Found \(availableMics.count) microphone(s) on system", level: .info)
        }
    }
    
    private func registerHotkey() {
        // Register the hotkey from settings
        if settings.hotkeyKeyCode != 0 && settings.hotkeyModifiers != 0 {
            let success = hotkeyManager.registerHotkey(
                keyCode: settings.hotkeyKeyCode,
                modifiers: settings.hotkeyModifiers
            )
            
            if success {
                logger.log("Registered global hotkey from settings", level: .info)
            } else {
                logger.log("Failed to register global hotkey", level: .error)
            }
        } else {
            logger.log("No hotkey defined in settings", level: .warning)
        }
    }
    
    func setupMenu() {
        logger.log("Setting up status bar menu")
        let menu = NSMenu()
        
        // Update microphone status on menu open
        menu.delegate = self
        
        // Microphone selection submenu
        let microphoneItem = NSMenuItem(title: "Microphone", action: nil, keyEquivalent: "")
        let microphoneSubmenu = NSMenu()
        microphoneItem.submenu = microphoneSubmenu
        menu.addItem(microphoneItem)
        
        // Only show permissions item if permissions are not granted
        if !AXIsProcessTrusted() {
            menu.addItem(NSMenuItem(title: "Refresh Permissions ⚠️", action: #selector(refreshPermissions), keyEquivalent: ""))
        }
        
        // Settings
        menu.addItem(NSMenuItem(title: "Settings", action: #selector(openSettings), keyEquivalent: ","))
        
        // Separator before bottom section
        menu.addItem(NSMenuItem.separator())
        
        // Logs
        menu.addItem(NSMenuItem(title: "View Logs", action: #selector(showLogs), keyEquivalent: "l"))
        
        // Version info - About section
        let aboutItem = NSMenuItem(title: "About", action: nil, keyEquivalent: "")
        let aboutSubmenu = NSMenu()
        
        // Version info
        let versionItem = NSMenuItem(title: "Version: \(VersionInfo.versionString)", action: nil, keyEquivalent: "")
        versionItem.isEnabled = false
        aboutSubmenu.addItem(versionItem)
        
        // Branch info (if not on main/master)
        if !["main", "master"].contains(VersionInfo.gitBranch) {
            let branchItem = NSMenuItem(title: "Branch: \(VersionInfo.gitBranch)", action: nil, keyEquivalent: "")
            branchItem.isEnabled = false
            aboutSubmenu.addItem(branchItem)
        }
        
        // Git hash (full)
        let hashItem = NSMenuItem(title: "Commit: \(VersionInfo.shortHash)", action: nil, keyEquivalent: "")
        hashItem.isEnabled = false
        aboutSubmenu.addItem(hashItem)
        
        aboutItem.submenu = aboutSubmenu
        menu.addItem(aboutItem)
        
        // Quit
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        
        statusItem.menu = menu
        logger.log("Status bar menu configured with Settings, Logs, About, and Quit options")
    }
    
    // Update the status bar icon based on microphone availability
    func updateStatusBarIcon() {
        // Check for available microphones
        checkForAvailableMicrophones()
        
        if let button = statusItem.button {
            let iconName = "waveform"
            let iconColor = hasMicrophones ? NSColor.controlAccentColor : NSColor.red
            
            let image = NSImage(systemSymbolName: iconName, accessibilityDescription: "Sheptun")?.tinted(with: iconColor)
            button.image = image
            logger.log("Status bar icon updated: color set to \(hasMicrophones ? "normal" : "red")")
        }
    }
    
    @objc func openSettings() {
        logger.log("Opening settings window", level: .info)
        
        if settingsWindow == nil {
            logger.log("Creating settings window", level: .debug)
            
            // Create the window with modern styling
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 700, height: 550),
                styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            window.center()
            window.title = "Sheptun Settings"
            window.titlebarAppearsTransparent = true
            window.isReleasedWhenClosed = false
            window.backgroundColor = NSColor.windowBackgroundColor
            window.isMovableByWindowBackground = true
            window.collectionBehavior = [.fullScreenAuxiliary]
            
            // Add visual effect view for modern appearance
            if let contentView = window.contentView {
                let visualEffectView = NSVisualEffectView()
                visualEffectView.blendingMode = .behindWindow
                visualEffectView.state = .active
                visualEffectView.material = .headerView
                contentView.addSubview(visualEffectView)
                visualEffectView.translatesAutoresizingMaskIntoConstraints = false
                NSLayoutConstraint.activate([
                    visualEffectView.topAnchor.constraint(equalTo: contentView.topAnchor),
                    visualEffectView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
                    visualEffectView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
                    visualEffectView.heightAnchor.constraint(equalToConstant: 82) // Title bar height
                ])
            }
            
            // Set the SwiftUI view as the window content
            let settingsView = SettingsView()
                .onDisappear {
                    // Re-register hotkey when settings view disappears (settings saved)
                    self.registerHotkey()
                }
            window.contentView = NSHostingView(rootView: settingsView)
            
            self.settingsWindow = window
            logger.log("Settings window created", level: .debug)
        }
        
        // Show and activate the window
        if let window = settingsWindow {
            logger.log("Showing settings window", level: .debug)
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
            NSApp.activate(ignoringOtherApps: true)
        }
    }
    
    @objc func showLogs() {
        logger.log("Show logs command triggered", level: .info)
        if let logURL = logger.getLogFileURL() {
            NSWorkspace.shared.open(logURL)
            logger.log("Opening log file in default text editor: \(logURL.path)")
        } else {
            logger.log("Unable to get log file URL", level: .error)
            
            let alert = NSAlert()
            alert.messageText = "Unable to Open Logs"
            alert.informativeText = "The log file could not be found."
            alert.alertStyle = .warning
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
    }
    
    // Add a method to check and request microphone permission
    private func checkMicrophonePermission() {
        let audioRecorder = AudioRecorder.shared
        
        if !audioRecorder.checkMicrophonePermission() {
            logger.log("Microphone permission not granted, requesting access", level: .warning)
            
            // Request microphone permission
            audioRecorder.requestMicrophonePermission { granted in
                if granted {
                    self.logger.log("Microphone access granted", level: .info)
                } else {
                    self.logger.log("Microphone access not granted", level: .warning)
                }
            }
        } else {
            logger.log("Microphone permission already granted", level: .info)
        }
    }
    
    // Add missing methods for recording functionality
    @objc func startRecording() {
        logger.log("Start recording command triggered", level: .info)
        // Implementation for starting recording
        // This is a placeholder - actual recording functionality should be implemented
        let audioRecorder = AudioRecorder.shared
        audioRecorder.startRecording()
    }
    
    @objc func stopRecording() {
        logger.log("Stop recording command triggered", level: .info)
        // Implementation for stopping recording
        // This is a placeholder - actual recording functionality should be implemented
        let audioRecorder = AudioRecorder.shared
        audioRecorder.stopRecording()
    }
    
    @objc func refreshPermissions() {
        logger.log("Refresh permissions triggered", level: .info)
        
        let accessibilityEnabled = AXIsProcessTrusted()
        
        if accessibilityEnabled {
            logger.log("Accessibility permissions are granted", level: .info)
            
            let alert = NSAlert()
            alert.messageText = "Permissions Status"
            alert.informativeText = "Accessibility permissions are enabled ✓"
            alert.alertStyle = .informational
            alert.addButton(withTitle: "OK")
            alert.runModal()
        } else {
            logger.log("Accessibility permissions are NOT granted", level: .warning)
            
            let alert = NSAlert()
            alert.messageText = "Permissions Required"
            alert.informativeText = "Sheptun needs accessibility permissions to use global hotkeys. Click 'Open Settings' to grant permissions."
            alert.alertStyle = .warning
            alert.addButton(withTitle: "Open Settings")
            alert.addButton(withTitle: "Cancel")
            
            let response = alert.runModal()
            if response == .alertFirstButtonReturn {
                // Open accessibility settings
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                    NSWorkspace.shared.open(url)
                    logger.log("Opening accessibility settings", level: .info)
                }
            }
        }
    }
}

// Helper extension to get RGB components from UIColor
extension NSColor {
    var rgbComponents: (red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) {
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0
        
        let convertedColor = self.usingColorSpace(.sRGB) ?? self
        convertedColor.getRed(&r, green: &g, blue: &b, alpha: &a)
        
        return (r, g, b, a)
    }
}

// Add extension for NSImage tinting
extension NSImage {
    func tinted(with color: NSColor) -> NSImage {
        let image = self.copy() as! NSImage
        image.lockFocus()
        
        color.set()
        let imageRect = NSRect(origin: .zero, size: image.size)
        imageRect.fill(using: .sourceAtop)
        
        image.unlockFocus()
        return image
    }
}

// Add NSMenuDelegate to update icon when menu is opened
extension AppDelegate: NSMenuDelegate {
    func menuWillOpen(_ menu: NSMenu) {
        // Update microphone status when menu opens
        updateStatusBarIcon()
        
        // Rebuild menu to update permissions item visibility
        setupMenu()
        
        // Update microphone submenu
        updateMicrophoneSubmenu()
    }
    
    private func updateMicrophoneSubmenu() {
        logger.log("Updating microphone submenu", level: .debug)
        
        // Find the microphone menu item
        guard let microphoneItem = statusItem.menu?.items.first(where: { $0.title == "Microphone" }),
              let submenu = microphoneItem.submenu else {
            logger.log("Could not find microphone submenu", level: .error)
            return
        }
        
        // Clear existing items
        submenu.removeAllItems()
        
        // Get available microphones
        let microphones = settings.getAvailableMicrophones()
        
        if microphones.isEmpty {
            let noMicItem = NSMenuItem(title: "No microphones available", action: nil, keyEquivalent: "")
            noMicItem.isEnabled = false
            submenu.addItem(noMicItem)
        } else {
            // Add header if there's a selected microphone
            if !settings.selectedMicrophoneID.isEmpty,
               let currentMic = microphones.first(where: { $0.id == settings.selectedMicrophoneID }) {
                let headerItem = NSMenuItem(title: "Current: \(currentMic.name)", action: nil, keyEquivalent: "")
                headerItem.isEnabled = false
                submenu.addItem(headerItem)
                submenu.addItem(NSMenuItem.separator())
            }
            
            // Add each microphone
            for mic in microphones {
                let micItem = NSMenuItem(
                    title: mic.name,
                    action: #selector(selectMicrophone(_:)),
                    keyEquivalent: ""
                )
                micItem.target = self
                micItem.representedObject = mic.id
                
                // Add checkmark to selected microphone
                if mic.id == settings.selectedMicrophoneID {
                    micItem.state = .on
                }
                
                submenu.addItem(micItem)
            }
        }
        
        // Add separator and refresh option
        submenu.addItem(NSMenuItem.separator())
        let refreshItem = NSMenuItem(
            title: "Refresh Microphones",
            action: #selector(refreshMicrophonesFromMenu),
            keyEquivalent: ""
        )
        refreshItem.target = self
        submenu.addItem(refreshItem)
        
        logger.log("Microphone submenu updated with \(microphones.count) devices", level: .debug)
    }
    
    @objc private func selectMicrophone(_ sender: NSMenuItem) {
        guard let microphoneID = sender.representedObject as? String else {
            logger.log("Failed to get microphone ID from menu item", level: .error)
            return
        }
        
        logger.log("Selecting microphone from menu: \(microphoneID)", level: .info)
        settings.selectedMicrophoneID = microphoneID
        settings.saveSettings()
        
        // Update the menu to reflect the new selection
        updateMicrophoneSubmenu()
    }
    
    @objc private func refreshMicrophonesFromMenu() {
        logger.log("Refreshing microphones from menu", level: .info)
        
        // Force update of available microphones and menu
        checkForAvailableMicrophones()
        updateStatusBarIcon()
        updateMicrophoneSubmenu()
    }
}
