
import Foundation

struct Track: Identifiable, Hashable {
    let id: String
    let title: String
    let albumId: String?
    let albumTitle: String?
    let artistName: String
    let duration: TimeInterval
    let trackNumber: Int?
    let discNumber: Int?
    let dateAdded: Date?
    let playCount: Int
    let isLiked: Bool
    let streamUrl: URL?   // Resolved from Jellyfin
    let serverId: UUID
}

