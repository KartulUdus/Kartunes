
import Foundation
import CoreFoundation
import OSLog

protocol AppLogger: Sendable {
    nonisolated func debug(_ message: @autoclosure () -> String)
    nonisolated func info(_ message: @autoclosure () -> String)
    nonisolated func warning(_ message: @autoclosure () -> String)
    nonisolated func error(_ message: @autoclosure () -> String)
}

enum LogCategory: String {
    case appCoordinator = "AppCoordinator"
    case settings       = "Settings"
    case home           = "Home"
    case auth           = "Auth"
    case playback       = "Playback"
    case nowPlaying     = "NowPlaying"
    case carPlay        = "CarPlay"
    case watch          = "Watch"
    case networking     = "Networking"
    case sync           = "Sync"
    case storage        = "Storage"
    case httpClient     = "HTTPClient"
    case serverDetect   = "ServerDetection"
    case siri           = "Siri"
}

struct Log {
    /// Creates a logger for the given category
    /// Nonisolated to allow creation from any context (actors, main actor, etc.)
    nonisolated static func make(_ category: LogCategory) -> AppLogger {
        OSLogLogger(category: category.rawValue)
    }
}

/// Thread-safe storage for device identifiers without requiring main actor access
enum DeviceIdentifierStore {
    private static let application = kCFPreferencesCurrentApplication
    
    static func loadOrCreateIdentifier(for key: String) -> String {
        if let existing = loadIdentifier(for: key) {
            return existing
        }
        let newId = UUID().uuidString
        saveIdentifier(newId, for: key)
        return newId
    }
    
    static func loadIdentifier(for key: String) -> String? {
        CFPreferencesCopyAppValue(key as CFString, application) as? String
    }
    
    static func saveIdentifier(_ value: String, for key: String) {
        CFPreferencesSetAppValue(key as CFString, value as CFPropertyList, application)
        CFPreferencesAppSynchronize(application)
    }
}
