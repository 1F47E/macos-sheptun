import Foundation

enum LogLevel: String {
    case debug = "DEBUG"
    case info = "INFO"
    case warning = "WARNING"
    case error = "ERROR"
}

class Logger {
    static let shared = Logger()
    private let fileManager = FileManager.default
    private let logFileName = "debug.log"
    private var logFileURL: URL?
    
    init() {
        setupLogFile()
    }
    
    private func setupLogFile() {
        do {
            let documentDirectory = try fileManager.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            let logDirectory = documentDirectory.appendingPathComponent("Sheptun", isDirectory: true)
            
            if !fileManager.fileExists(atPath: logDirectory.path) {
                try fileManager.createDirectory(at: logDirectory, withIntermediateDirectories: true)
            }
            
            logFileURL = logDirectory.appendingPathComponent(logFileName)
            
            // Add app start marker to log
            log("=== Application Started ===", level: .info)
        } catch {
            print("Error setting up log file: \(error)")
        }
    }
    
    func log(_ message: String, level: LogLevel = .debug, file: String = #file, function: String = #function, line: Int = #line) {
        let fileName = (file as NSString).lastPathComponent
        let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .short, timeStyle: .medium)
        let logMessage = "[\(timestamp)] [\(level.rawValue)] [\(fileName):\(line) \(function)] \(message)\n"
        
        // Print to console with formatting for visibility
        switch level {
        case .error:
            print("🔴 ERROR: \(logMessage)", terminator: "")
        case .warning:
            print("⚠️ WARNING: \(logMessage)", terminator: "")
        case .info:
            print("ℹ️ \(logMessage)", terminator: "")
        case .debug:
            #if DEBUG
            print("🔍 \(logMessage)", terminator: "")
            #endif
        }
        
        // Write to file
        guard let logFileURL = logFileURL else { return }
        
        do {
            if fileManager.fileExists(atPath: logFileURL.path) {
                let fileHandle = try FileHandle(forWritingTo: logFileURL)
                fileHandle.seekToEndOfFile()
                if let data = logMessage.data(using: .utf8) {
                    fileHandle.write(data)
                }
                fileHandle.closeFile()
            } else {
                try logMessage.write(to: logFileURL, atomically: true, encoding: .utf8)
            }
        } catch {
            print("Error writing to log file: \(error)")
        }
    }
    
    func getLogFileURL() -> URL? {
        return logFileURL
    }
} 