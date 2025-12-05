
import Foundation

struct Artist: Identifiable, Hashable {
    let id: String        // Jellyfin ItemId
    let name: String
    let thumbnailURL: URL?
}

