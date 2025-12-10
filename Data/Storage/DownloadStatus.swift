import Foundation
import CoreData

/// Download status for offline tracks
enum DownloadStatus: Int16, Codable {
    case notDownloaded = 0
    case queued = 1
    case downloading = 2
    case downloaded = 3
    case failed = 4
}

/// Helper to manage download status for tracks
/// Since we can't modify Core Data model directly, we use a separate tracking system
final class DownloadStatusManager {
    private static let userDefaultsKey = "com.kartul.kartunes.downloadStatus"
    private static let userDefaults = UserDefaults.standard
    
    /// Get download status for a track
    static func getStatus(for trackId: String) -> DownloadStatus {
        guard let data = userDefaults.data(forKey: userDefaultsKey),
              let statusMap = try? JSONDecoder().decode([String: Int16].self, from: data),
              let rawValue = statusMap[trackId],
              let status = DownloadStatus(rawValue: rawValue) else {
            return .notDownloaded
        }
        return status
    }
    
    /// Set download status for a track
    static func setStatus(_ status: DownloadStatus, for trackId: String) {
        var statusMap: [String: Int16] = [:]
        if let data = userDefaults.data(forKey: userDefaultsKey),
           let decoded = try? JSONDecoder().decode([String: Int16].self, from: data) {
            statusMap = decoded
        }
        
        statusMap[trackId] = status.rawValue
        if let encoded = try? JSONEncoder().encode(statusMap) {
            userDefaults.set(encoded, forKey: userDefaultsKey)
        }
    }
    
    /// Remove status for a track
    static func removeStatus(for trackId: String) {
        guard var statusMap = try? JSONDecoder().decode([String: Int16].self, from: userDefaults.data(forKey: userDefaultsKey) ?? Data()) else {
            return
        }
        statusMap.removeValue(forKey: trackId)
        if let encoded = try? JSONEncoder().encode(statusMap) {
            userDefaults.set(encoded, forKey: userDefaultsKey)
        }
    }
    
    /// Get all tracks with a specific status
    static func getTrackIds(with status: DownloadStatus) -> [String] {
        guard let data = userDefaults.data(forKey: userDefaultsKey),
              let statusMap = try? JSONDecoder().decode([String: Int16].self, from: data) else {
            return []
        }
        return statusMap.compactMap { trackId, rawValue in
            DownloadStatus(rawValue: rawValue) == status ? trackId : nil
        }
    }
    
    /// Clean up statuses for deleted tracks
    static func cleanupStatuses(for existingTrackIds: Set<String>) {
        guard let data = userDefaults.data(forKey: userDefaultsKey),
              var statusMap = try? JSONDecoder().decode([String: Int16].self, from: data) else {
            return
        }
        
        let keysToRemove = statusMap.keys.filter { !existingTrackIds.contains($0) }
        for key in keysToRemove {
            statusMap.removeValue(forKey: key)
        }
        
        if let encoded = try? JSONEncoder().encode(statusMap) {
            userDefaults.set(encoded, forKey: userDefaultsKey)
        }
    }
}

