
import Foundation
@preconcurrency import CoreData

/// Handles syncing playlists from the media server to Core Data
final class MediaServerPlaylistSyncer {
    private let apiClient: MediaServerAPIClient
    private let coreDataStack: CoreDataStack
    private let logger: AppLogger
    
    init(apiClient: MediaServerAPIClient, coreDataStack: CoreDataStack, logger: AppLogger = Log.make(.sync)) {
        self.apiClient = apiClient
        self.coreDataStack = coreDataStack
        self.logger = logger
    }
    
    /// Syncs playlists from the media server to Core Data
    func syncPlaylists(
        for server: CDServer,
        progressCallback: @escaping (SyncProgress) -> Void = { _ in }
    ) async throws {
        let serverObjectID = server.objectID
        let context = coreDataStack.newBackgroundContext()
        
        let playlistDTOs = try await apiClient.fetchPlaylists()
        
        try await context.perform {
            let serverInContext = try context.existingObject(with: serverObjectID) as! CDServer
            
            let sourceValue = self.apiClient.serverType == .jellyfin ? "jellyfin" : "emby"
            let existingPlaylistsRequest: NSFetchRequest<CDPlaylist> = CDPlaylist.fetchRequest()
            existingPlaylistsRequest.predicate = NSPredicate(format: "server == %@ AND source == %@", serverInContext, sourceValue)
            let existingPlaylists = try context.fetch(existingPlaylistsRequest)
            var existingPlaylistMap: [String: CDPlaylist] = [:]
            for playlist in existingPlaylists {
                if let id = playlist.id {
                    existingPlaylistMap[id] = playlist
                }
            }
            
            let remotePlaylistIds = Set(playlistDTOs.map { $0.id })
            
            for dto in playlistDTOs {
                let cdPlaylist: CDPlaylist
                if let existing = existingPlaylistMap[dto.id] {
                    cdPlaylist = existing
                } else {
                    cdPlaylist = CDPlaylist(context: context)
                    cdPlaylist.id = dto.id
                    cdPlaylist.server = serverInContext
                }
                
                cdPlaylist.source = sourceValue
                cdPlaylist.name = dto.name
                cdPlaylist.summary = dto.summary
                cdPlaylist.ownerUserId = dto.ownerUserId
                
                cdPlaylist.isReadOnly = dto.isFileBased(serverType: self.apiClient.serverType)
                
                if cdPlaylist.createdAt == nil {
                    cdPlaylist.createdAt = Date()
                }
                cdPlaylist.updatedAt = Date()
            }
            
            for (id, cdPlaylist) in existingPlaylistMap {
                if !remotePlaylistIds.contains(id) {
                    context.delete(cdPlaylist)
                }
            }
            
            try context.save()
            self.logger.info("Synced \(playlistDTOs.count) playlists")
        }
    }
}

