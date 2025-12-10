
import Foundation
import OSLog

@available(iOS 14.0, watchOS 7.0, *)
final class OSLogLogger: AppLogger {
    nonisolated private let logger: Logger
    nonisolated private let subsystem: String
    nonisolated private let category: String
    
    #if DEBUG
    nonisolated private let enableConsoleOutput = true
    #else
    nonisolated private let enableConsoleOutput = false
    #endif

    nonisolated init(subsystem: String? = nil, category: String) {
        let subsystemValue = subsystem ?? Bundle.main.bundleIdentifier ?? "com.kartul.Kartunes"
        self.subsystem = subsystemValue
        self.category = category
        self.logger = Logger(subsystem: subsystemValue, category: category)
    }

    nonisolated func debug(_ message: @autoclosure () -> String) {
        let msg = message()
        logger.debug("\(msg, privacy: .public)")
        if enableConsoleOutput {
            print("[DEBUG][\(category)] \(msg)")
        }
    }

    nonisolated func info(_ message: @autoclosure () -> String) {
        let msg = message()
        logger.info("\(msg, privacy: .public)")
        if enableConsoleOutput {
            print("[INFO][\(category)] \(msg)")
        }
    }

    nonisolated func warning(_ message: @autoclosure () -> String) {
        let msg = message()
        logger.warning("\(msg, privacy: .public)")
        if enableConsoleOutput {
            print("[WARNING][\(category)] \(msg)")
        }
    }

    nonisolated func error(_ message: @autoclosure () -> String) {
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

