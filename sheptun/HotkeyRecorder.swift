import SwiftUI
import Carbon

struct HotkeyRecorder: View {
    @Binding var keyCode: UInt
    @Binding var modifiers: UInt
    @State private var isRecording = false
    @State private var displayText = ""
    @Environment(\.dismiss) private var dismiss
    private let logger = Logger.shared
    
    var body: some View {
        VStack(spacing: 0) {
            // Title bar with close button
            HStack {
                Text("Set Hotkey")
                    .font(.headline)
                Spacer()
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                        .font(.title2)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.escape)
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))
            
            Divider()
            
            // Main content
            VStack(spacing: 24) {
                // Instructions
                Text("Press the key combination you want to use")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                
                // Large centered hotkey display
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(isRecording ? Color.accentColor.opacity(0.1) : Color(NSColor.controlBackgroundColor))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .strokeBorder(isRecording ? Color.accentColor : Color(NSColor.separatorColor), lineWidth: 2)
                        )
                    
                    if displayText.isEmpty {
                        Text("No shortcut set")
                            .font(.system(size: 24, weight: .light, design: .monospaced))
                            .foregroundColor(.secondary)
                    } else {
                        Text(displayText)
                            .font(.system(size: 36, weight: .medium, design: .monospaced))
                            .foregroundColor(isRecording ? .accentColor : .primary)
                    }
                }
                .frame(height: 80)
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
                    Label(
                        isRecording ? "Recording... Press keys" : "Record Shortcut",
                        systemImage: isRecording ? "record.circle.fill" : "keyboard"
                    )
                    .frame(minWidth: 200)
                }
                .controlSize(.large)
                .buttonStyle(.borderedProminent)
                
                // Requirements note
                Text("Requires ⌘ Command + ⇧ Shift + any key")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(32)
        }
        .frame(width: 450, height: 300)
        .background(Color(NSColor.windowBackgroundColor))
        .onAppear {
            updateDisplayText()
            logger.log("HotkeyRecorder appeared, current hotkey: \(displayText)")
        }
    }
    
    private func handleKeyEvent(_ event: NSEvent) {
        if event.type == .keyDown {
            keyCode = UInt(event.keyCode)
            modifiers = event.modifierFlags.rawValue & (NSEvent.ModifierFlags.command.rawValue | NSEvent.ModifierFlags.shift.rawValue | NSEvent.ModifierFlags.control.rawValue | NSEvent.ModifierFlags.option.rawValue)
            
            logger.log("Key event captured: keyCode=\(keyCode), modifiers=\(modifiers)")
            
            if isValidHotkey() {
                isRecording = false
                updateDisplayText()
                logger.log("Valid hotkey recorded: \(displayText)")
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