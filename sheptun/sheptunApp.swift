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
    private var debugAnimationWindow: NSWindow?
    private var transcribeDebugWindow: NSWindow?
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
        
        // Transcribe Debug
        menu.addItem(NSMenuItem(title: "Transcribe Debug", action: #selector(openTranscribeDebugWindow), keyEquivalent: "d"))
        
        // Logs
        menu.addItem(NSMenuItem(title: "Logs", action: #selector(showLogs), keyEquivalent: "l"))
        
        // Animation Debug
        menu.addItem(NSMenuItem(title: "Animation Debug", action: #selector(openAnimationDebugWindow), keyEquivalent: "a"))
        
        // Settings
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Settings", action: #selector(openSettings), keyEquivalent: ","))
        
        // Quit
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        
        statusItem.menu = menu
        logger.log("Status bar menu configured with Settings, Animation Debug, Transcribe Debug, and Quit options")
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
            
            // Create the window
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 500, height: 350),
                styleMask: [.titled, .closable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            window.center()
            window.title = "Sheptun Settings"
            window.titlebarAppearsTransparent = true
            window.isReleasedWhenClosed = false
            window.backgroundColor = NSColor.windowBackgroundColor
            
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
    
    @objc func openAnimationDebugWindow() {
        logger.log("Opening Animation Debug Window", level: .info)
        
        if let existingWindow = debugAnimationWindow, !existingWindow.isVisible {
            existingWindow.makeKeyAndOrderFront(nil)
            return
        }
        
        if debugAnimationWindow == nil {
            let contentView = AnimationDebugView()
            debugAnimationWindow = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 600, height: 500),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            debugAnimationWindow?.center()
            debugAnimationWindow?.title = "Animation Debug"
            debugAnimationWindow?.isReleasedWhenClosed = false
            debugAnimationWindow?.contentView = NSHostingView(rootView: contentView)
        }
        
        debugAnimationWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    @objc func openTranscribeDebugWindow() {
        logger.log("Opening Transcribe Debug Window", level: .info)
        
        if let existingWindow = transcribeDebugWindow, !existingWindow.isVisible {
            existingWindow.makeKeyAndOrderFront(nil)
            return
        }
        
        if transcribeDebugWindow == nil {
            let contentView = TranscribeDebugView()
            transcribeDebugWindow = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 600, height: 500),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            transcribeDebugWindow?.center()
            transcribeDebugWindow?.title = "Transcribe Debug"
            transcribeDebugWindow?.isReleasedWhenClosed = false
            transcribeDebugWindow?.contentView = NSHostingView(rootView: contentView)
        }
        
        transcribeDebugWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
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
    }
}
