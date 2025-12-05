
import Foundation

enum MediaServerType: String, CaseIterable, Codable {
    case jellyfin
    case emby
    
    var displayName: String {
        switch self {
        case .jellyfin:
            return "Jellyfin"
        case .emby:
            return "Emby"
        }
    }
}

