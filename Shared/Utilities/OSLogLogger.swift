
import Foundation
import OSLog

@available(iOS 14.0, watchOS 7.0, *)
final class OSLogLogger: AppLogger {
    private let logger: Logger
    private let subsystem: String
    private let category: String
    
    #if DEBUG
    private let enableConsoleOutput = true
    #else
    private let enableConsoleOutput = false
    #endif

    init(subsystem: String? = nil, category: String) {
        let subsystemValue = subsystem ?? Bundle.main.bundleIdentifier ?? "com.kartul.Kartunes"
        self.subsystem = subsystemValue
        self.category = category
        self.logger = Logger(subsystem: subsystemValue, category: category)
    }

    func debug(_ message: @autoclosure () -> String) {
        let msg = message()
        logger.debug("\(msg, privacy: .public)")
        if enableConsoleOutput {
            print("[DEBUG][\(category)] \(msg)")
        }
    }

    func info(_ message: @autoclosure () -> String) {
        let msg = message()
        logger.info("\(msg, privacy: .public)")
        if enableConsoleOutput {
            print("[INFO][\(category)] \(msg)")
        }
    }

    func warning(_ message: @autoclosure () -> String) {
        let msg = message()
        logger.warning("\(msg, privacy: .public)")
        if enableConsoleOutput {
            print("[WARNING][\(category)] \(msg)")
        }
    }

    func error(_ message: @autoclosure () -> String) {
        let msg = message()
        logger.error("\(msg, privacy: .public)")
        if enableConsoleOutput {
            print("[ERROR][\(category)] \(msg)")
        }
    }
    
    var subsystemIdentifier: String {
        subsystem
    }
}

