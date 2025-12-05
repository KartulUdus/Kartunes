
import Foundation

struct Playlist: Identifiable, Hashable {
    let id: String
    let name: String
    let summary: String?
    let isSmart: Bool
    let source: PlaylistSource
    let isReadOnly: Bool
    let createdAt: Date?
    let updatedAt: Date?
    
    var isEditable: Bool {
        // All playlists come from Jellyfin, but file-based ones (M3U) are read-only
        return !isReadOnly && source == .jellyfin
    }
}

enum PlaylistSource: String, Hashable {
    case jellyfin = "jellyfin"
}

