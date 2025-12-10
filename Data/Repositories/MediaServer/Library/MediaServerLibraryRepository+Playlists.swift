
import Foundation
@preconcurrency import CoreData

extension MediaServerLibraryRepository {
    func syncPlaylists() async throws {
        let context = coreDataStack.viewContext
        
        guard let cdServer = try await context.perform({
            let serverRequest: NSFetchRequest<CDServer> = CDServer.fetchRequest()
            serverRequest.predicate = NSPredicate(format: "id == %@", self.serverId as CVarArg)
            serverRequest.fetchLimit = 1
            return try context.fetch(serverRequest).first
        }) else {
            self.logger.error("Server not found in Core Data for syncPlaylists (serverId: \(self.serverId))")
            throw LibraryRepositoryError.serverNotFound
        }
        
        let syncManager = await MainActor.run {
            MediaServerSyncManager.create(apiClient: apiClient, coreDataStack: coreDataStack)
        }
        try await syncManager.syncPlaylists(for: cdServer.objectID)
    }
    
    func createPlaylist(name: String, summary: String?) async throws -> Playlist {
        // Create playlist on media server
        let dto = try await apiClient.createPlaylist(name: name)
        
        // Save to Core Data
        let context = coreDataStack.viewContext
        return try await context.perform {
            let serverRequest: NSFetchRequest<CDServer> = CDServer.fetchRequest()
            serverRequest.predicate = NSPredicate(format: "id == %@", self.serverId as CVarArg)
            serverRequest.fetchLimit = 1
            guard let server = try context.fetch(serverRequest).first else {
                self.logger.error("Server not found in Core Data for createPlaylist (serverId: \(self.serverId))")
                throw LibraryRepositoryError.serverNotFound
            }
            
            let playlist = CDPlaylist(context: context)
            playlist.id = dto.id
            playlist.name = dto.name
            playlist.summary = summary ?? dto.summary
            playlist.source = "jellyfin"
            playlist.isReadOnly = dto.isFileBased(serverType: self.apiClient.serverType)
            playlist.isSmart = false
            playlist.createdAt = Date()
            playlist.updatedAt = Date()
            playlist.server = server
            
            do {
                try context.save()
            } catch {
                self.logger.error("Failed to save Core Data context after creating playlist: \(error)")
                throw error
            }
            
            return Playlist(
                id: playlist.id ?? "",
                name: playlist.name ?? "",
                summary: playlist.summary,
                isSmart: playlist.isSmart,
                source: .jellyfin,
                isReadOnly: playlist.isReadOnly,
                createdAt: playlist.createdAt,
                updatedAt: playlist.updatedAt
            )
        }
    }
    
    func addTracksToPlaylist(playlistId: String, trackIds: [String]) async throws {
        try await apiClient.addTracksToPlaylist(playlistId: playlistId, trackIds: trackIds)
        
        // Optionally update local cache - for now just sync from server
        // In a future enhancement, we could optimistically update Core Data
    }
    
    func removeTracksFromPlaylist(playlistId: String, entryIds: [String]) async throws {
        try await apiClient.removeTracksFromPlaylist(playlistId: playlistId, entryIds: entryIds)
        
        // Optionally update local cache - for now just sync from server
    }
    
    func deletePlaylist(playlistId: String) async throws {
        // Delete from media server
        try await apiClient.deletePlaylist(playlistId: playlistId)
        
        // Also delete from Core Data
        let context = coreDataStack.viewContext
        try await context.perform {
            let request: NSFetchRequest<CDPlaylist> = CDPlaylist.fetchRequest()
            request.predicate = NSPredicate(format: "id == %@", playlistId)
            request.fetchLimit = 1
            if let cdPlaylist = try context.fetch(request).first {
                context.delete(cdPlaylist)
                do {
                    try context.save()
                } catch {
                    self.logger.error("Failed to save Core Data context after deleting playlist: \(error)")
                    throw error
                }
            }
        }
    }
    
    func fetchPlaylistEntryIds(playlistId: String) async throws -> [String: String] {
        let dtos = try await apiClient.fetchPlaylistItems(playlistId: playlistId)
        return Dictionary(uniqueKeysWithValues: dtos.compactMap { dto in
            guard let entryId = dto.playlistItemId else { return nil }
            return (dto.id, entryId)
        })
    }
    
    func movePlaylistItem(playlistId: String, playlistItemId: String, newIndex: Int) async throws {
        try await apiClient.movePlaylistItem(playlistId: playlistId, playlistItemId: playlistItemId, newIndex: newIndex)
    }
    
    func fetchPlaylists() async throws -> [Playlist] {
        // Fetch from Core Data
        let context = coreDataStack.viewContext
        return try await context.perform {
            let serverRequest: NSFetchRequest<CDServer> = CDServer.fetchRequest()
            serverRequest.predicate = NSPredicate(format: "id == %@", self.serverId as CVarArg)
            serverRequest.fetchLimit = 1
            guard let cdServer = try context.fetch(serverRequest).first else {
                return [Playlist]()
            }
            
            let request: NSFetchRequest<CDPlaylist> = CDPlaylist.fetchRequest()
            request.predicate = NSPredicate(format: "server == %@", cdServer)
            request.sortDescriptors = [NSSortDescriptor(key: "name", ascending: true)]
            
            let cdPlaylists = try context.fetch(request)
            return cdPlaylists.map { cdPlaylist in
                // All playlists are from Jellyfin now (no local playlists)
                let sourceString = cdPlaylist.source ?? "jellyfin"
                let source = PlaylistSource(rawValue: sourceString) ?? .jellyfin
                
                return Playlist(
                    id: cdPlaylist.id ?? "",
                    name: cdPlaylist.name ?? "",
                    summary: cdPlaylist.summary,
                    isSmart: cdPlaylist.isSmart,
                    source: source,
                    isReadOnly: cdPlaylist.isReadOnly,
                    createdAt: cdPlaylist.createdAt,
                    updatedAt: cdPlaylist.updatedAt
                )
            }
        }
    }
    
    func fetchPlaylistTracks(playlistId: String) async throws -> [Track] {
        let context = coreDataStack.viewContext
        
        // First, get the playlist to check its source
        let playlistRequest: NSFetchRequest<CDPlaylist> = CDPlaylist.fetchRequest()
        playlistRequest.predicate = NSPredicate(format: "id == %@", playlistId)
        playlistRequest.fetchLimit = 1
        
        guard let cdPlaylist = try await context.perform({
            try context.fetch(playlistRequest).first
        }) else {
            self.logger.error("Playlist not found in Core Data (playlistId: \(playlistId))")
            throw LibraryRepositoryError.invalidPlaylistId
        }
        
        // All playlists are Jellyfin-managed now, but we check if tracks are cached locally
        // For file-based playlists, we always fetch from API
        // For server-managed playlists, we can check Core Data first, then fall back to API
        let isReadOnly = cdPlaylist.isReadOnly
        let playlistObjectID = cdPlaylist.objectID
        
        // For read-only (file-based) playlists, always fetch from API
        // For editable playlists, try Core Data first if tracks exist
        if !isReadOnly, let tracksSet = cdPlaylist.tracks, tracksSet.count > 0 {
            return await context.perform {
                guard let cdPlaylistInContext = try? context.existingObject(with: playlistObjectID) as? CDPlaylist,
                      let tracksSet = cdPlaylistInContext.tracks else {
                    return [Track]()
                }
                
                let cdTracks = tracksSet.array.compactMap { $0 as? CDTrack }
                
                return cdTracks.map { cdTrack in
                    let streamUrl = cdTrack.id.flatMap { trackId in
                        self.apiClient.buildStreamURL(forTrackId: trackId)
                    }
                    
                    return Track(
                        id: cdTrack.id ?? "",
                        title: cdTrack.title ?? "",
                        albumId: cdTrack.album?.id,
                        albumTitle: cdTrack.album?.title,
                        artistName: cdTrack.artist?.name ?? "Unknown Artist",
                        duration: cdTrack.duration,
                        trackNumber: cdTrack.trackNumber > 0 ? Int(cdTrack.trackNumber) : nil,
                        discNumber: cdTrack.discNumber > 0 ? Int(cdTrack.discNumber) : nil,
                        dateAdded: cdTrack.dateAdded,
                        playCount: Int(cdTrack.playCount),
                        isLiked: cdTrack.isLiked,
                        streamUrl: streamUrl,
                        serverId: self.serverId
                    )
                }
            }
        }
        
        // If it's a Jellyfin playlist, fetch from API
        // Store entry IDs for removal operations
        let dtos = try await apiClient.fetchPlaylistItems(playlistId: playlistId)
        
        // Get up-to-date isLiked status from CoreData for all tracks
        let coreDataLikedStatus = await context.perform {
            let trackIds = dtos.map { $0.id }
            let trackRequest: NSFetchRequest<CDTrack> = CDTrack.fetchRequest()
            trackRequest.predicate = NSPredicate(format: "id IN %@", trackIds)
            
            let cdTracks = try? context.fetch(trackRequest)
            var likedMap: [String: Bool] = [:]
            cdTracks?.forEach { cdTrack in
                if let trackId = cdTrack.id {
                    likedMap[trackId] = cdTrack.isLiked
                }
            }
            return likedMap
        }
        
        return dtos.map { dto in
            // Use CoreData isLiked if available (most up-to-date), otherwise fall back to API
            let isLiked = coreDataLikedStatus[dto.id] ?? (dto.userData?.isFavorite ?? false)
            return Track(dto: dto, serverId: serverId, apiClient: apiClient, isLiked: isLiked)
        }
    }
}
