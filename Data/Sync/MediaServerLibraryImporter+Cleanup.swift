
import Foundation
@preconcurrency import CoreData

enum CleanupPhase {
    static func removeDeletedEntities(
        state: ExistingLibraryState,
        remoteArtistIDs: Set<String>,
        remoteAlbumIDs: Set<String>,
        remoteTrackIDs: Set<String>,
        in context: NSManagedObjectContext,
        logger: AppLogger
    ) {
        let artistsToDelete = Array(state.artists.values).filter { artist in
            guard let artistId = artist.id else { return false }
            return !remoteArtistIDs.contains(artistId)
        }
        if !artistsToDelete.isEmpty {
            logger.info("Deleting \(artistsToDelete.count) artists")
            for artist in artistsToDelete {
                context.delete(artist)
            }
        }
        
        let albumsToDelete = Array(state.albums.values).filter { album in
            guard let albumId = album.id else { return false }
            return !remoteAlbumIDs.contains(albumId)
        }
        if !albumsToDelete.isEmpty {
            logger.info("Deleting \(albumsToDelete.count) albums")
            for album in albumsToDelete {
                context.delete(album)
            }
        }
        
        let tracksToDelete = Array(state.tracks.values).filter { track in
            guard let trackId = track.id else { return false }
            return !remoteTrackIDs.contains(trackId)
        }
        if !tracksToDelete.isEmpty {
            logger.info("Deleting \(tracksToDelete.count) tracks")
            
            // Clean up downloads for deleted tracks
            let deletedTrackIds = Set(tracksToDelete.compactMap { $0.id })
            Task { @MainActor in
                for trackId in deletedTrackIds {
                    do {
                        try OfflineDownloadManager.shared.deleteDownload(for: trackId)
                    } catch {
                        logger.warning("Failed to delete download for track \(trackId): \(error.localizedDescription)")
                    }
                }
            }
            
            for track in tracksToDelete {
                context.delete(track)
            }
        }
    }
}

