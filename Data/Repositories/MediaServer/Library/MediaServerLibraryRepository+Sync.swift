
import Foundation
@preconcurrency import CoreData

extension MediaServerLibraryRepository {
    func refreshLibrary() async throws {
        // Use the sync manager for full sync
        let context = coreDataStack.viewContext
        
        guard let cdServer = try await context.perform({
            let serverRequest: NSFetchRequest<CDServer> = CDServer.fetchRequest()
            serverRequest.predicate = NSPredicate(format: "id == %@", self.serverId as CVarArg)
            serverRequest.fetchLimit = 1
            return try context.fetch(serverRequest).first
        }) else {
            self.logger.error("Server not found in Core Data for refreshLibrary (serverId: \(serverId))")
            throw LibraryRepositoryError.serverNotFound
        }
        
        let syncManager = await MainActor.run {
            MediaServerSyncManager.create(apiClient: apiClient, coreDataStack: coreDataStack)
        }
        try await syncManager.performFullSync(for: cdServer)
    }
    
    /// Syncs missing tracks, albums, artists, and genres to CoreData for the given track DTOs
    func syncMissingMetadata(for trackDTOs: [JellyfinTrackDTO]) async throws {
        let context = coreDataStack.viewContext
        
        guard let cdServer = try await context.perform({
            let serverRequest: NSFetchRequest<CDServer> = CDServer.fetchRequest()
            serverRequest.predicate = NSPredicate(format: "id == %@", self.serverId as CVarArg)
            serverRequest.fetchLimit = 1
            return try context.fetch(serverRequest).first
        }) else {
            self.logger.error("Server not found in Core Data for syncMissingMetadata (serverId: \(serverId))")
            throw LibraryRepositoryError.serverNotFound
        }
        
        // Collect unique album IDs and artist names from tracks
        var albumIds = Set<String>()
        var artistNames = Set<String>()
        var genreNames = Set<String>()
        
        for dto in trackDTOs {
            if let albumId = dto.albumId {
                albumIds.insert(albumId)
            }
            if let artists = dto.artists {
                artistNames.formUnion(artists)
            }
            if let genres = dto.genres {
                genreNames.formUnion(genres)
            }
        }
        
        // Check what exists in CoreData first
        let serverObjectID = cdServer.objectID
        let (existingAlbumMap, existingArtistMap, existingGenreMap) = try await context.perform {
            // Get server in this context
            let serverInContext = try context.existingObject(with: serverObjectID) as! CDServer
            
            // Fetch existing albums
            let existingAlbumsRequest: NSFetchRequest<CDAlbum> = CDAlbum.fetchRequest()
            existingAlbumsRequest.predicate = NSPredicate(format: "id IN %@ AND server == %@", Array(albumIds), serverInContext)
            let existingAlbums = try context.fetch(existingAlbumsRequest)
            var albumMap: [String: CDAlbum] = [:]
            for album in existingAlbums {
                if let id = album.id {
                    albumMap[id] = album
                }
            }
            
            // Fetch existing artists - use case-insensitive matching
            // First, fetch all artists for this server to do case-insensitive matching
            let allArtistsRequest: NSFetchRequest<CDArtist> = CDArtist.fetchRequest()
            allArtistsRequest.predicate = NSPredicate(format: "server == %@", serverInContext)
            let allArtists = try context.fetch(allArtistsRequest)
            var artistMap: [String: CDArtist] = [:]
            // Build a case-insensitive lookup map
            var artistNameToArtist: [String: CDArtist] = [:]
            for artist in allArtists {
                if let name = artist.name {
                    // Store both exact match and lowercase match for case-insensitive lookup
                    artistNameToArtist[name.lowercased()] = artist
                    artistMap[name] = artist
                }
            }
            // Now match artist names case-insensitively
            for artistName in artistNames {
                if let matchedArtist = artistNameToArtist[artistName.lowercased()] {
                    artistMap[artistName] = matchedArtist
                }
            }
            
            // Fetch existing genres
            let existingGenresRequest: NSFetchRequest<CDGenre> = CDGenre.fetchRequest()
            existingGenresRequest.predicate = NSPredicate(format: "normalizedName IN %@ AND server == %@", Array(genreNames.map { UmbrellaGenres.normalize($0) }), serverInContext)
            let existingGenres = try context.fetch(existingGenresRequest)
            var genreMap: [String: CDGenre] = [:]
            for genre in existingGenres {
                if let normalized = genre.normalizedName {
                    genreMap[normalized] = genre
                }
            }
            
            return (albumMap, artistMap, genreMap)
        }
        
        // Identify missing albums and fetch them from API
        let missingAlbumIds = albumIds.filter { existingAlbumMap[$0] == nil }
        var missingAlbums: [JellyfinAlbumDTO] = []
        if !missingAlbumIds.isEmpty {
            self.logger.info("Fetching \(missingAlbumIds.count) missing albums")
            // Fetch all albums and filter for missing ones
            let allAlbums = try await apiClient.fetchAlbums(byArtistId: nil as String?)
            missingAlbums = allAlbums.filter { missingAlbumIds.contains($0.id) }
        }
        
        // Identify missing artists - check case-insensitively
        let missingArtistNames = artistNames.filter { artistName in
            // Check if we have this artist (case-insensitive)
            !existingArtistMap.values.contains { artist in
                artist.name?.caseInsensitiveCompare(artistName) == .orderedSame
            }
        }
        
        // For missing artists, we'll create placeholder records in CoreData
        // instead of fetching all artists from the API (which is slow and can timeout)
        // The full sync will populate them properly later
        if !missingArtistNames.isEmpty {
            self.logger.warning("Found \(missingArtistNames.count) artists not in CoreData: \(missingArtistNames.prefix(5).joined(separator: ", "))\(missingArtistNames.count > 5 ? "..." : "")")
            self.logger.info("Will create placeholder artist records - full sync will populate them properly")
        }
        
        // Now sync everything to CoreData
        let serverObjectID2 = cdServer.objectID
        // Extract IDs from maps to avoid capturing non-Sendable CoreData objects
        let albumIdsFromMap = Set(existingAlbumMap.keys)
        let genreNormalizedNamesFromMap = Set(existingGenreMap.keys)
        
        try await context.perform {
            // Get server in this context
            let serverInContext = try context.existingObject(with: serverObjectID2) as! CDServer
            
            // Rebuild maps in this context
            var albumMap: [String: CDAlbum] = [:]
            if !albumIdsFromMap.isEmpty {
                let albumRequest: NSFetchRequest<CDAlbum> = CDAlbum.fetchRequest()
                albumRequest.predicate = NSPredicate(format: "id IN %@ AND server == %@", Array(albumIdsFromMap), serverInContext)
                if let albums = try? context.fetch(albumRequest) {
                    for album in albums {
                        if let id = album.id {
                            albumMap[id] = album
                        }
                    }
                }
            }
            
            var artistMap: [String: CDArtist] = [:]
            // Fetch all artists for case-insensitive matching
            let allArtistsRequest: NSFetchRequest<CDArtist> = CDArtist.fetchRequest()
            allArtistsRequest.predicate = NSPredicate(format: "server == %@", serverInContext)
            if let allArtists = try? context.fetch(allArtistsRequest) {
                // Build case-insensitive lookup
                var artistNameToArtist: [String: CDArtist] = [:]
                for artist in allArtists {
                    if let name = artist.name {
                        artistNameToArtist[name.lowercased()] = artist
                    }
                }
                // Match requested artist names case-insensitively
                for artistName in artistNames {
                    if let matchedArtist = artistNameToArtist[artistName.lowercased()] {
                        artistMap[artistName] = matchedArtist
                    }
                }
            }
            
            var genreMap: [String: CDGenre] = [:]
            if !genreNormalizedNamesFromMap.isEmpty {
                let genreRequest: NSFetchRequest<CDGenre> = CDGenre.fetchRequest()
                genreRequest.predicate = NSPredicate(format: "normalizedName IN %@ AND server == %@", Array(genreNormalizedNamesFromMap), serverInContext)
                if let genres = try? context.fetch(genreRequest) {
                    for genre in genres {
                        if let normalized = genre.normalizedName {
                            genreMap[normalized] = genre
                        }
                    }
                }
            }
            
            // Create missing albums
            for albumDTO in missingAlbums {
                let artistName = albumDTO.artistName
                let artist = artistName.flatMap { artistMap[$0] }
                let cdAlbum = CDAlbum.upsert(from: albumDTO, artist: artist, server: serverInContext, apiClient: self.apiClient, in: context)
                albumMap[albumDTO.id] = cdAlbum
            }
            
            // Create missing artists as placeholders
            // We don't fetch from API to avoid timeout - full sync will populate them properly
            for artistName in missingArtistNames {
                // Check if artist already exists by name (case-insensitive) - might have been created in a previous iteration
                let existingArtist = artistMap.values.first { artist in
                    artist.name?.caseInsensitiveCompare(artistName) == .orderedSame
                }
                
                if let existing = existingArtist {
                    // Use existing artist
                    artistMap[artistName] = existing
                } else {
                    // Create minimal placeholder artist
                    // The ID will be empty for now - full sync will populate it
                    let cdArtist = CDArtist(context: context)
                    cdArtist.id = "" // Will be populated by full sync
                    cdArtist.name = artistName
                    cdArtist.sortName = artistName
                    cdArtist.server = serverInContext
                    artistMap[artistName] = cdArtist
                    self.logger.debug("Created placeholder artist: \(artistName)")
                }
            }
            
            // Create missing genres
            for genreName in genreNames {
                let normalized = UmbrellaGenres.normalize(genreName)
                if genreMap[normalized] == nil {
                    let cdGenre = CDGenre.upsert(rawName: genreName, server: serverInContext, in: context)
                    genreMap[normalized] = cdGenre
                }
            }
            
            // Bulk fetch existing tracks to avoid individual lookups
            let trackIds = Set(trackDTOs.map { $0.id })
            let existingTracksRequest: NSFetchRequest<CDTrack> = CDTrack.fetchRequest()
            existingTracksRequest.predicate = NSPredicate(format: "id IN %@ AND server == %@", Array(trackIds), serverInContext)
            let existingTracks = try? context.fetch(existingTracksRequest)
            var existingTrackMap: [String: CDTrack] = [:]
            for track in existingTracks ?? [] {
                if let id = track.id {
                    existingTrackMap[id] = track
                }
            }
            
            let newTrackCount = trackIds.count - existingTrackMap.count
            if newTrackCount > 0 {
                self.logger.info("Found \(newTrackCount) new tracks out of \(trackDTOs.count) total")
            } else {
                self.logger.debug("All \(trackDTOs.count) tracks already exist in CoreData")
            }
            
            // Sync tracks - use existing tracks from map to avoid individual fetches
            for dto in trackDTOs {
                let album = dto.albumId.flatMap { albumMap[$0] }
                // Use case-insensitive artist matching
                let artist = dto.artists?.first.flatMap { artistName in
                    artistMap[artistName] ?? artistMap.values.first { $0.name?.caseInsensitiveCompare(artistName) == .orderedSame }
                } ?? album?.artist
                
                let splitGenres = UmbrellaGenres.splitGenres(dto.genres ?? [])
                let trackGenres = Set(splitGenres.compactMap { genreName in
                    genreMap[UmbrellaGenres.normalize(genreName)]
                })
                
                // Use existing track from map if available, otherwise let upsert create it
                let existingTrack = existingTrackMap[dto.id]
                _ = CDTrack.upsert(from: dto, album: album, artist: artist, genres: trackGenres, server: serverInContext, existingTrack: existingTrack, in: context)
            }
            
            do {
                try context.save()
                self.logger.info("Synced metadata for \(trackDTOs.count) tracks")
            } catch {
                self.logger.error("Failed to save Core Data context after syncing metadata: \(error)")
                throw error
            }
        }
    }
    
    func syncLikedTracks() async throws {
        // Fetch all liked tracks from API
        let likedTrackDTOs = try await apiClient.fetchLikedTracks(limit: nil as Int?)
        
        guard !likedTrackDTOs.isEmpty else {
            self.logger.info("No liked tracks found on server")
            // Still need to update local tracks to remove isLiked if they're no longer liked
            try await updateLikedStatus(serverLikedTrackIds: Set<String>())
            return
        }
        
        // Sync missing metadata for liked tracks
        try await syncMissingMetadata(for: likedTrackDTOs)
        
        // Get server liked track IDs
        let serverLikedTrackIds = Set(likedTrackDTOs.map { $0.id })
        
        // Update liked status for all tracks in CoreData
        try await updateLikedStatus(serverLikedTrackIds: serverLikedTrackIds)
        
        self.logger.info("Synced liked tracks - \(likedTrackDTOs.count) liked on server")
    }
    
    private func updateLikedStatus(serverLikedTrackIds: Set<String>) async throws {
        let context = coreDataStack.viewContext
        
        let serverObjectID: NSManagedObjectID? = try await context.perform {
            let serverRequest: NSFetchRequest<CDServer> = CDServer.fetchRequest()
            serverRequest.predicate = NSPredicate(format: "id == %@", self.serverId as CVarArg)
            serverRequest.fetchLimit = 1
            guard let server = try context.fetch(serverRequest).first else {
                return nil
            }
            return server.objectID
        }
        
        guard let serverObjectID = serverObjectID else {
            self.logger.error("Server not found in Core Data for updateLikedStatus (serverId: \(serverId))")
            throw LibraryRepositoryError.serverNotFound
        }
        
        try await context.perform {
            // Get server in this context
            let serverInContext = try context.existingObject(with: serverObjectID) as! CDServer
            
            // Fetch all tracks for this server
            let trackRequest: NSFetchRequest<CDTrack> = CDTrack.fetchRequest()
            trackRequest.predicate = NSPredicate(format: "server == %@", serverInContext)
            
            guard let allTracks = try? context.fetch(trackRequest) else {
                return
            }
            
            var updatedCount = 0
            for cdTrack in allTracks {
                guard let trackId = cdTrack.id else { continue }
                
                let shouldBeLiked = serverLikedTrackIds.contains(trackId)
                if cdTrack.isLiked != shouldBeLiked {
                    cdTrack.isLiked = shouldBeLiked
                    updatedCount += 1
                }
            }
            
            if updatedCount > 0 {
                do {
                    try context.save()
                    self.logger.info("Updated liked status for \(updatedCount) tracks")
                } catch {
                    self.logger.error("Failed to save Core Data context after updating liked status: \(error)")
                    throw error
                }
            }
        }
    }
}

