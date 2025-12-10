
import Foundation

/// Defines where the playback queue came from, which influences ordering
enum PlaybackContext: Equatable {
    case album(albumId: String)
    case artist(artistId: String)
    case playlist(playlistId: String)
    case allSongs(sortedBy: TrackSortOption, ascending: Bool)
    case searchResults(query: String)
    case instantMix(seedItemId: String) // InstantMix/Radio from a seed item
    case genre(genreName: String, isUmbrella: Bool)
    case offlineDownloads // Offline downloaded tracks
    case custom([String]) // fallback for future
}

