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
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        logger.log("Application did finish launching", level: .info)
        
        // Hide dock icon
        NSApp.setActivationPolicy(.accessory)
        
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "waveform", accessibilityDescription: "Sheptun")
            logger.log("Status bar button created with waveform icon")
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
        
        menu.addItem(NSMenuItem(title: "Settings", action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Debug Animation", action: #selector(openDebugAnimation), keyEquivalent: "d"))
        menu.addItem(NSMenuItem(title: "Transcribe Debug", action: #selector(openTranscribeDebug), keyEquivalent: "t"))
        menu.addItem(NSMenuItem(title: "Show Logs", action: #selector(showLogs), keyEquivalent: "l"))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        
        statusItem.menu = menu
        logger.log("Status bar menu configured with Settings, Debug Animation, Transcribe Debug, Show Logs, and Quit options")
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
    
    @objc func openDebugAnimation() {
        logger.log("Opening debug animation window", level: .info)
        
        if debugAnimationWindow == nil {
            logger.log("Creating debug animation window", level: .debug)
            
            // Create the window
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 500, height: 400),
                styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            window.center()
            window.title = "Animation Debug"
            window.titlebarAppearsTransparent = true
            window.isReleasedWhenClosed = false
            window.backgroundColor = NSColor.windowBackgroundColor
            
            // Set the SwiftUI view as the window content
            let debugView = DebugAnimationView()
            window.contentView = NSHostingView(rootView: debugView)
            
            self.debugAnimationWindow = window
            logger.log("Debug animation window created", level: .debug)
        }
        
        // Show and activate the window
        if let window = debugAnimationWindow {
            logger.log("Showing debug animation window", level: .debug)
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
            NSApp.activate(ignoringOtherApps: true)
        }
    }
    
    @objc func openTranscribeDebug() {
        logger.log("Opening transcribe debug window", level: .info)
        
        if transcribeDebugWindow == nil {
            logger.log("Creating transcribe debug window", level: .debug)
            
            // Create the window
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
                styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            window.center()
            window.title = "Transcribe Debug"
            window.titlebarAppearsTransparent = true
            window.isReleasedWhenClosed = false
            window.backgroundColor = NSColor.windowBackgroundColor
            
            // Set the SwiftUI view as the window content
            let transcribeDebugView = TranscribeDebugView()
            window.contentView = NSHostingView(rootView: transcribeDebugView)
            
            self.transcribeDebugWindow = window
            logger.log("Transcribe debug window created", level: .debug)
        }
        
        // Show and activate the window
        if let window = transcribeDebugWindow {
            logger.log("Showing transcribe debug window", level: .debug)
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}

// MARK: - Debug Animation View
struct DebugAnimationView: View {
    @State private var intensity: Float = 0.5
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Animation Debug")
                .font(.title2)
                .padding(.top)
            
            // Animation module display area
            ParticleWaveEffect(intensity: intensity)
                .baseColor(.blue)
                .accentColor(.purple)
                .height(200)
                .padding()
                .background(Color(.windowBackgroundColor).opacity(0.2))
                .cornerRadius(12)
                .padding(.horizontal)
            
            // Control panel
            VStack(spacing: 10) {
                Text("Intensity: \(String(format: "%.2f", intensity))")
                    .font(.headline)
                
                HStack {
                    Text("0.0")
                    Slider(value: $intensity, in: 0...1)
                        .padding(.horizontal)
                    Text("1.0")
                }
                
                HStack(spacing: 20) {
                    Button("0.25") { intensity = 0.25 }
                    Button("0.5") { intensity = 0.5 }
                    Button("0.75") { intensity = 0.75 }
                    Button("1.0") { intensity = 1.0 }
                }
            }
            .padding()
            .background(Color(.windowBackgroundColor).opacity(0.2))
            .cornerRadius(12)
            .padding(.horizontal)
            
            Spacer()
        }
        .frame(minWidth: 500, minHeight: 400)
    }
}
