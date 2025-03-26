import Cocoa
import Carbon

class HotkeyManager {
    static let shared = HotkeyManager()
    
    private var eventHandler: EventHandlerRef?
    private var hotKeyRef: EventHotKeyRef?
    private var registered = false
    private var hotKeyID = EventHotKeyID()
    private let logger = Logger.shared
    
    private init() {
        // Initialize with a unique signature
        hotKeyID.signature = fourCharCodeFrom("SHPT")
        hotKeyID.id = 1
    }
    
    deinit {
        unregisterHotkey()
    }
    
    func registerHotkey(keyCode: UInt, modifiers: UInt) -> Bool {
        guard keyCode != 0 && modifiers != 0 else {
            logger.log("Cannot register hotkey: keyCode or modifiers are not set", level: .warning)
            return false
        }
        
        // Unregister existing hotkey first if any
        if registered {
            unregisterHotkey()
        }
        
        // Convert Swift UInt modifiers to Carbon modifiers
        var carbonModifiers: UInt32 = 0
        
        if modifiers & NSEvent.ModifierFlags.command.rawValue != 0 {
            carbonModifiers |= UInt32(cmdKey)
        }
        if modifiers & NSEvent.ModifierFlags.shift.rawValue != 0 {
            carbonModifiers |= UInt32(shiftKey)
        }
        if modifiers & NSEvent.ModifierFlags.control.rawValue != 0 {
            carbonModifiers |= UInt32(controlKey)
        }
        if modifiers & NSEvent.ModifierFlags.option.rawValue != 0 {
            carbonModifiers |= UInt32(optionKey)
        }
        
        // Register the event handler
        var eventType = EventTypeSpec()
        eventType.eventClass = OSType(kEventClassKeyboard)
        eventType.eventKind = OSType(kEventHotKeyPressed)
        
        // Reference to self for the callback
        let selfPtr = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            { (_, event, userData) -> OSStatus in
                guard let userData = userData else { return noErr }
                let hotKeyManager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
                return hotKeyManager.handleHotkeyEvent(event: event!)
            },
            1,
            &eventType,
            selfPtr,
            &eventHandler
        )
        
        if status != noErr {
            logger.log("Failed to install event handler: \(status)", level: .error)
            return false
        }
        
        // Register the hotkey
        let registerStatus = RegisterEventHotKey(
            UInt32(keyCode),
            carbonModifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        
        if registerStatus != noErr {
            logger.log("Failed to register hotkey: \(registerStatus)", level: .error)
            return false
        }
        
        registered = true
        logger.log("Hotkey registered successfully: keyCode=\(keyCode), carbonModifiers=\(carbonModifiers)", level: .info)
        return true
    }
    
    func unregisterHotkey() {
        if let hotKeyRef = hotKeyRef {
            let status = UnregisterEventHotKey(hotKeyRef)
            if status != noErr {
                logger.log("Failed to unregister hotkey: \(status)", level: .error)
            } else {
                logger.log("Hotkey unregistered successfully", level: .info)
            }
            self.hotKeyRef = nil
        }
        
        if let eventHandler = eventHandler {
            let status = RemoveEventHandler(eventHandler)
            if status != noErr {
                logger.log("Failed to remove event handler: \(status)", level: .error)
            } else {
                logger.log("Event handler removed successfully", level: .info)
            }
            self.eventHandler = nil
        }
        
        registered = false
    }
    
    private func handleHotkeyEvent(event: EventRef) -> OSStatus {
        var hotkeyID = EventHotKeyID()
        let status = GetEventParameter(
            event,
            UInt32(kEventParamDirectObject),
            UInt32(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &hotkeyID
        )
        
        if status != noErr {
            logger.log("Failed to get hotkey event parameter: \(status)", level: .error)
            return status
        }
        
        if hotkeyID.id == hotKeyID.id {
            logger.log("Hotkey pressed!", level: .info)
            
            // Toggle the popup window
            DispatchQueue.main.async {
                PopupWindowManager.shared.toggleRecording()
            }
        }
        
        return noErr
    }
    
    private func fourCharCodeFrom(_ string: String) -> FourCharCode {
        var result: FourCharCode = 0
        let chars = string.utf8
        var index = 0
        for char in chars {
            guard index < 4 else { break }
            result |= FourCharCode(char) << (8 * (3 - index))
            index += 1
        }
        return result
    }
} 