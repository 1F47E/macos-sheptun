import SwiftUI
import Carbon

struct HotkeyRecorder: View {
    @Binding var keyCode: UInt
    @Binding var modifiers: UInt
    @State private var isRecording = false
    @State private var displayText = ""
    private let logger = Logger.shared
    
    var body: some View {
        HStack {
            Text(displayText.isEmpty ? "No shortcut set" : displayText)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            Button(isRecording ? "Press keys..." : "Record") {
                isRecording.toggle()
                logger.log("Hotkey recording \(isRecording ? "started" : "stopped")")
                if isRecording {
                    NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { event in
                        handleKeyEvent(event)
                        return nil
                    }
                }
            }
        }
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
        default:
            logger.log("Unknown key code: \(keyCode)", level: .warning)
            return nil
        }
    }
} 