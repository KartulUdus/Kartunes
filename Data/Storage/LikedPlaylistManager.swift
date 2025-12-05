
import Foundation
@preconcurrency import CoreData

/// Manages the automatic "Kartunes Liked {userName}" playlist
final class LikedPlaylistManager {
    private let libraryRepository: LibraryRepository
    private let coreDataStack: CoreDataStack
    private let serverId: UUID
    private let logger: AppLogger
    
    init(libraryRepository: LibraryRepository, coreDataStack: CoreDataStack, serverId: UUID, logger: AppLogger = Log.make(.storage)) {
        self.libraryRepository = libraryRepository
        self.coreDataStack = coreDataStack
        self.serverId = serverId
        self.logger = logger
    }
    
    /// Gets or creates the "Kartunes Liked {userName}" playlist
    private func getOrCreateLikedPlaylist() async throws -> Playlist {
        let context = coreDataStack.viewContext
        let username = try await context.perform {
            let serverRequest: NSFetchRequest<CDServer> = CDServer.fetchRequest()
            serverRequest.predicate = NSPredicate(format: "id == %@", self.serverId as CVarArg)
            serverRequest.fetchLimit = 1
            guard let server = try context.fetch(serverRequest).first else {
                throw LikedPlaylistError.serverNotFound
            }
            return server.username ?? ""
        }
        
        guard !username.isEmpty else {
            throw LikedPlaylistError.usernameNotFound
        }
        
        let playlistName = "Kartunes Liked \(username)"
        
        let existingPlaylist: CDPlaylist? = try await context.perform {
            let serverRequest: NSFetchRequest<CDServer> = CDServer.fetchRequest()
            serverRequest.predicate = NSPredicate(format: "id == %@", self.serverId as CVarArg)
            serverRequest.fetchLimit = 1
            
            guard let server = try context.fetch(serverRequest).first else {
                return nil as CDPlaylist?
            }
            
            let playlistRequest: NSFetchRequest<CDPlaylist> = CDPlaylist.fetchRequest()
            playlistRequest.predicate = NSPredicate(format: "name == %@ AND server == %@", playlistName, server)
            playlistRequest.fetchLimit = 1
            return try context.fetch(playlistRequest).first
        }
        
        if let existing = existingPlaylist,
           let playlistId = existing.id {
            return Playlist(
                id: playlistId,
                name: existing.name ?? playlistName,
                summary: existing.summary,
                isSmart: existing.isSmart,
                source: .jellyfin,
                isReadOnly: existing.isReadOnly,
                createdAt: existing.createdAt,
                updatedAt: existing.updatedAt
            )
        }
        
        logger.info("Creating new liked playlist: \(playlistName)")
        let playlist = try await libraryRepository.createPlaylist(name: playlistName, summary: nil)
        return playlist
    }
    
    /// Adds a track to the liked playlist at index 0 (top)
    func addTrackToLikedPlaylist(trackId: String) async throws {
        let playlist = try await getOrCreateLikedPlaylist()
        
        let tracks = try await libraryRepository.fetchPlaylistTracks(playlistId: playlist.id)
        if tracks.contains(where: { $0.id == trackId }) {
            let entryIds = try await libraryRepository.fetchPlaylistEntryIds(playlistId: playlist.id)
            guard let entryId = entryIds[trackId] else {
                logger.warning("Track found in playlist but entry ID not found")
                return
            }
            
            try await libraryRepository.movePlaylistItem(
                playlistId: playlist.id,
                playlistItemId: entryId,
                newIndex: 0
            )
            logger.info("Moved track to top of liked playlist")
        } else {
            try await libraryRepository.addTracksToPlaylist(playlistId: playlist.id, trackIds: [trackId])
            
            let entryIds = try await libraryRepository.fetchPlaylistEntryIds(playlistId: playlist.id)
            guard let entryId = entryIds[trackId] else {
                logger.warning("Track added but entry ID not found")
                return
            }
            
            try await libraryRepository.movePlaylistItem(
                playlistId: playlist.id,
                playlistItemId: entryId,
                newIndex: 0
            )
            logger.info("Added track to top of liked playlist")
        }
    }
    
    /// Removes a track from the liked playlist
    func removeTrackFromLikedPlaylist(trackId: String) async throws {
        let playlist = try await getOrCreateLikedPlaylist()
        
        let entryIds = try await libraryRepository.fetchPlaylistEntryIds(playlistId: playlist.id)
        guard let entryId = entryIds[trackId] else {
            logger.info("Track not in liked playlist, nothing to remove")
            return
        }
        
        try await libraryRepository.removeTracksFromPlaylist(playlistId: playlist.id, entryIds: [entryId])
        logger.info("Removed track from liked playlist")
    }
}

enum LikedPlaylistError: Error {
    case serverNotFound
    case usernameNotFound
}

