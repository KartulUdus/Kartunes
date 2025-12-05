
import Foundation

// MARK: - Message Types

enum WatchMessageType: String, Codable {
    case command
    case state
    case requestState
}

enum WatchCommand: String, Codable {
    case playPause
    case next
    case previous
    case seek
    case toggleFavourite
    case radioFromCurrentTrack
}

enum PlaybackState: String, Codable {
    case playing
    case paused
    case stopped
}

// MARK: - Message Models

struct WatchCommandMessage: Codable {
    let type: WatchMessageType
    let command: WatchCommand
    let seekTime: TimeInterval? // Optional, only used for seek command
}

struct WatchStateMessage: Codable {
    let type: WatchMessageType
    let track: TrackSummary?
    let playbackState: PlaybackState
    let position: TimeInterval
    let duration: TimeInterval
}

struct WatchRequestStateMessage: Codable {
    let type: WatchMessageType
}

// MARK: - Track Summary (lightweight version for Watch)

struct TrackSummary: Codable {
    let id: String
    let title: String
    let artist: String
    let album: String?
    let isFavourite: Bool
    let albumArtURL: String?
}

#if !os(watchOS)
import CoreData

// Extension only available on iOS (where Track is defined)
extension TrackSummary {
    init(from track: Track, apiClient: MediaServerAPIClient? = nil, coreDataStack: CoreDataStack? = nil) {
        self.id = track.id
        self.title = track.title
        self.artist = track.artistName
        self.album = track.albumTitle
        self.isFavourite = track.isLiked
        
        // Try to get album art URL from CoreData first (faster and more reliable)
        var albumArtURLString: String? = nil
        
        if let albumId = track.albumId {
            // Try CoreData first
            if let stack = coreDataStack {
                let context = stack.viewContext
                let request: NSFetchRequest<CDAlbum> = CDAlbum.fetchRequest()
                request.predicate = NSPredicate(format: "id == %@", albumId)
                request.fetchLimit = 1
                if let cdAlbum = try? context.fetch(request).first,
                   let imageURL = cdAlbum.imageURL {
                    albumArtURLString = imageURL
                }
            }
            
            // Fallback to building URL if not in CoreData
            if albumArtURLString == nil, let client = apiClient {
                // Use smaller size for watch (watch screens are small)
                albumArtURLString = client.buildImageURL(forItemId: albumId, imageType: "Primary", maxWidth: 200)?.absoluteString
            }
        }
        
        self.albumArtURL = albumArtURLString
    }
}
#endif

