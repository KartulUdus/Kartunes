
import Foundation
import OSLog

protocol AppLogger {
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

