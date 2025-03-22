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
        
        // Debug output for the API key
        if !settings.openAIKey.isEmpty {
            logger.log("App started with API key: \(settings.maskAPIKey(settings.openAIKey))")
            print("App started with API key: \(settings.maskAPIKey(settings.openAIKey))")
        } else {
            logger.log("App started with no API key set", level: .warning)
            print("App started with no API key set")
        }
    }
    
    func setupMenu() {
        logger.log("Setting up status bar menu")
        let menu = NSMenu()
        
        menu.addItem(NSMenuItem(title: "Settings", action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Show Logs", action: #selector(showLogs), keyEquivalent: "l"))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        
        statusItem.menu = menu
        logger.log("Status bar menu configured with Settings, Show Logs, and Quit options")
    }
    
    @objc func openSettings() {
        logger.log("Opening settings window", level: .info)
        
        if settingsWindow == nil {
            logger.log("Creating settings window", level: .debug)
            
            // Create the window
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 400, height: 200),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            window.center()
            window.title = "Sheptun Settings"
            window.isReleasedWhenClosed = false
            
            // Set the SwiftUI view as the window content
            let settingsView = SettingsView()
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
}
