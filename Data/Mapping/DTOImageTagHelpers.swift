
import Foundation

extension JellyfinAlbumDTO {
    /// Returns the primary image tag, handling case-insensitive matching
    var primaryImageTag: String? {
        imageTags?["Primary"] ?? imageTags?["primary"]
    }
}

extension JellyfinArtistDTO {
    /// Returns the primary image tag, handling case-insensitive matching
    var primaryImageTag: String? {
        imageTags?["Primary"] ?? imageTags?["primary"]
    }
}

