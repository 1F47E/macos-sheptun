import SwiftUI
import Carbon

struct HotkeyRecorder: View {
    let initialKeyCode: UInt
    let initialModifiers: UInt
    let onSave: (UInt, UInt) -> Void
    
    @State private var keyCode: UInt = 0
    @State private var modifiers: UInt = 0
    @State private var isRecording = false
    @State private var displayText = ""
    @State private var hasChanges = false
    @Environment(\.dismiss) private var dismiss
    private let logger = Logger.shared
    
    var body: some View {
        VStack(spacing: 20) {
            // Compact hotkey display
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(isRecording ? Color.accentColor.opacity(0.1) : Color(NSColor.controlBackgroundColor))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(isRecording ? Color.accentColor : Color(NSColor.separatorColor), lineWidth: 2)
                    )
                
                if displayText.isEmpty {
                    Text("⌘⇧ + key")
                        .font(.system(size: 24, weight: .light, design: .monospaced))
                        .foregroundColor(.secondary)
                } else {
                    Text(displayText)
                        .font(.system(size: 32, weight: .medium, design: .monospaced))
                        .foregroundColor(hasChanges ? .accentColor : .primary)
                }
            }
            .frame(height: 70)
            .animation(.easeInOut(duration: 0.2), value: isRecording)
            
            // Record button
            Button(action: {
                isRecording.toggle()
                logger.log("Hotkey recording \(isRecording ? "started" : "stopped")")
                if isRecording {
                    NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { event in
                        handleKeyEvent(event)
                        return nil
                    }
                }
            }) {
                if isRecording {
                    Label("Recording...", systemImage: "record.circle.fill")
                } else {
                    Label("Record", systemImage: "keyboard")
                }
            }
            .controlSize(.large)
            .buttonStyle(.borderedProminent)
            .disabled(isRecording && hasChanges)
            
            // Action buttons
            HStack(spacing: 12) {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.escape)
                
                Button("Save") {
                    onSave(keyCode, modifiers)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!hasChanges || keyCode == 0)
            }
        }
        .padding(24)
        .frame(width: 300, height: 220)
        .background(Color(NSColor.windowBackgroundColor))
        .onAppear {
            // Initialize with current values
            keyCode = initialKeyCode
            modifiers = initialModifiers
            updateDisplayText()
            logger.log("HotkeyRecorder appeared with initial hotkey: \(displayText)")
        }
    }
    
    private func handleKeyEvent(_ event: NSEvent) {
        if event.type == .keyDown {
            let newKeyCode = UInt(event.keyCode)
            let newModifiers = event.modifierFlags.rawValue & (NSEvent.ModifierFlags.command.rawValue | NSEvent.ModifierFlags.shift.rawValue | NSEvent.ModifierFlags.control.rawValue | NSEvent.ModifierFlags.option.rawValue)
            
            logger.log("Key event captured: keyCode=\(newKeyCode), modifiers=\(newModifiers)")
            
            // Update local state
            keyCode = newKeyCode
            modifiers = newModifiers
            
            if isValidHotkey() {
                isRecording = false
                updateDisplayText()
                // Check if this is different from the initial values
                hasChanges = (keyCode != initialKeyCode || modifiers != initialModifiers)
                logger.log("Valid hotkey recorded: \(displayText), hasChanges: \(hasChanges)")
            } else {
                logger.log("Invalid hotkey combination (requires Command+Shift)", level: .warning)
            }
        }
    }
    
    private func isValidHotkey() -> Bool {
        let hasCommand = modifiers & NSEvent.ModifierFlags.command.rawValue != 0
        let hasShift = modifiers & NSEvent.ModifierFlags.shift.rawValue != 0
        return hasCommand && hasShift && keyCode != 0
    }
    
    private func updateDisplayText() {
        var text = ""
        
        if modifiers & NSEvent.ModifierFlags.command.rawValue != 0 {
            text += "⌘"
        }
        if modifiers & NSEvent.ModifierFlags.shift.rawValue != 0 {
            text += "⇧"
        }
        if modifiers & NSEvent.ModifierFlags.control.rawValue != 0 {
            text += "⌃"
        }
        if modifiers & NSEvent.ModifierFlags.option.rawValue != 0 {
            text += "⌥"
        }
        
        if keyCode != 0 {
            if let chars = keyCodeToString(keyCode) {
                text += chars
            }
        }
        
        displayText = text
        logger.log("Updated hotkey display text: \(displayText)")
    }
    
    private func keyCodeToString(_ keyCode: UInt) -> String? {
        switch keyCode {
        case 0: return "A"
        case 1: return "S"
        case 2: return "D"
        case 3: return "F"
        case 4: return "H"
        case 5: return "G"
        case 6: return "Z"
        case 7: return "X"
        case 8: return "C"
        case 9: return "V"
        case 11: return "B"
        case 12: return "Q"
        case 13: return "W"
        case 14: return "E"
        case 15: return "R"
        case 16: return "Y"
        case 17: return "T"
        case 31: return "O"
        case 32: return "U"
        case 34: return "I"
        case 35: return "P"
        case 37: return "L"
        case 38: return "J"
        case 40: return "K"
        case 45: return "N"
        case 46: return "M"
        case 18: return "1"
        case 19: return "2"
        case 20: return "3"
        case 21: return "4"
        case 23: return "5"
        case 22: return "6"
        case 26: return "7"
        case 28: return "8"
        case 25: return "9"
        case 29: return "0"
        case 49: return "Space"
        case 36: return "Return"
        case 48: return "Tab"
        case 51: return "Delete"
        case 53: return "Escape"
        default:
            logger.log("Unknown key code: \(keyCode)", level: .warning)
            return "Key\(keyCode)"
        }
    }
}

// Helper view to display hotkey text
struct HotkeyDisplayText: View {
    let keyCode: UInt16
    let modifiers: UInt
    
    var body: some View {
        Text(formattedHotkey)
    }
    
    private var formattedHotkey: String {
        var text = ""
        
        if modifiers & NSEvent.ModifierFlags.command.rawValue != 0 {
            text += "⌘"
        }
        if modifiers & NSEvent.ModifierFlags.shift.rawValue != 0 {
            text += "⇧"
        }
        if modifiers & NSEvent.ModifierFlags.control.rawValue != 0 {
            text += "⌃"
        }
        if modifiers & NSEvent.ModifierFlags.option.rawValue != 0 {
            text += "⌥"
        }
        
        if keyCode != 0 {
            text += keyCodeToString(keyCode) ?? "Key\(keyCode)"
        }
        
        return text
    }
    
    private func keyCodeToString(_ keyCode: UInt16) -> String? {
        switch keyCode {
        case 0: return "A"
        case 1: return "S"
        case 2: return "D"
        case 3: return "F"
        case 4: return "H"
        case 5: return "G"
        case 6: return "Z"
        case 7: return "X"
        case 8: return "C"
        case 9: return "V"
        case 11: return "B"
        case 12: return "Q"
        case 13: return "W"
        case 14: return "E"
        case 15: return "R"
        case 16: return "Y"
        case 17: return "T"
        case 31: return "O"
        case 32: return "U"
        case 34: return "I"
        case 35: return "P"
        case 37: return "L"
        case 38: return "J"
        case 40: return "K"
        case 45: return "N"
        case 46: return "M"
        case 18: return "1"
        case 19: return "2"
        case 20: return "3"
        case 21: return "4"
        case 23: return "5"
        case 22: return "6"
        case 26: return "7"
        case 28: return "8"
        case 25: return "9"
        case 29: return "0"
        case 49: return "Space"
        case 36: return "Return"
        case 48: return "Tab"
        case 51: return "Delete"
        case 53: return "Escape"
        default: return nil
        }
    }
}