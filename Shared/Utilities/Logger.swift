
import Foundation
import OSLog

protocol AppLogger {
    func debug(_ message: @autoclosure () -> String)
    func info(_ message: @autoclosure () -> String)
    func warning(_ message: @autoclosure () -> String)
    func error(_ message: @autoclosure () -> String)
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
    static func make(_ category: LogCategory) -> AppLogger {
        OSLogLogger(category: category.rawValue)
    }
}

