
import Foundation
@preconcurrency import CoreData

extension MediaServerLibraryRepository {
    func fetchArtists() async throws -> [Artist] {
        // Try Core Data first
        let context = coreDataStack.viewContext
        let cachedArtists: [Artist] = try await context.perform {
            let serverRequest: NSFetchRequest<CDServer> = CDServer.fetchRequest()
            serverRequest.predicate = NSPredicate(format: "id == %@", self.serverId as CVarArg)
            serverRequest.fetchLimit = 1
            guard let cdServer = try context.fetch(serverRequest).first else {
                return [Artist]()
            }
            
            let request: NSFetchRequest<CDArtist> = CDArtist.fetchRequest()
            request.predicate = NSPredicate(format: "server == %@", cdServer)
            request.sortDescriptors = [NSSortDescriptor(key: "sortName", ascending: true)]
            
            let cdArtists = try context.fetch(request)
            return cdArtists.map { cdArtist in
                Artist(
                    id: cdArtist.id ?? "",
                    name: cdArtist.name ?? "",
                    thumbnailURL: cdArtist.imageURL.flatMap { URL(string: $0) }
                )
            }
        }
        
        if !cachedArtists.isEmpty {
            return cachedArtists
        }
        
        // Fall back to API
        let dtos = try await apiClient.fetchArtists()
        return dtos.map { dto in
            Artist(dto: dto, apiClient: apiClient)
        }
    }
    func fetchAlbums(artistId: String?) async throws -> [Album] {
        // Try Core Data first
        let context = coreDataStack.viewContext
        let cachedAlbums: [Album] = try await context.perform {
            let serverRequest: NSFetchRequest<CDServer> = CDServer.fetchRequest()
            serverRequest.predicate = NSPredicate(format: "id == %@", self.serverId as CVarArg)
            serverRequest.fetchLimit = 1
            guard let cdServer = try context.fetch(serverRequest).first else {
                return [Album]()
            }
            
            let request: NSFetchRequest<CDAlbum> = CDAlbum.fetchRequest()
            if let artistId = artistId {
                // Find artist first
                let artistRequest: NSFetchRequest<CDArtist> = CDArtist.fetchRequest()
                artistRequest.predicate = NSPredicate(format: "id == %@ AND server == %@", artistId, cdServer)
                artistRequest.fetchLimit = 1
                if let artist = try context.fetch(artistRequest).first {
                    request.predicate = NSPredicate(format: "artist == %@ AND server == %@", artist, cdServer)
                } else {
                    return []
                }
            } else {
                request.predicate = NSPredicate(format: "server == %@", cdServer)
            }
            request.sortDescriptors = [NSSortDescriptor(key: "sortTitle", ascending: true)]
            
            let cdAlbums = try context.fetch(request)
            return cdAlbums.map { cdAlbum in
                Album(
                    id: cdAlbum.id ?? "",
                    title: cdAlbum.title ?? "",
                    artistName: cdAlbum.artist?.name ?? "Unknown Artist",
                    thumbnailURL: cdAlbum.imageURL.flatMap { URL(string: $0) },
                    year: cdAlbum.year > 0 ? Int(cdAlbum.year) : nil
                )
            }
        }
        
        if !cachedAlbums.isEmpty {
            return cachedAlbums
        }
        
        // Fall back to API
        let dtos = try await apiClient.fetchAlbums(byArtistId: artistId)
        return dtos.map { dto in
            Album(dto: dto, apiClient: apiClient)
        }
    }
    func fetchTracks(albumId: String?) async throws -> [Track] {
        // Try Core Data first
        let context = coreDataStack.viewContext
        let cachedTracks: [Track] = try await context.perform {
            let serverRequest: NSFetchRequest<CDServer> = CDServer.fetchRequest()
            serverRequest.predicate = NSPredicate(format: "id == %@", self.serverId as CVarArg)
            serverRequest.fetchLimit = 1
            guard let cdServer = try context.fetch(serverRequest).first else {
                self.logger.warning("Server not found in Core Data for album tracks")
                return [Track]()
            }
            
            let cdTracks: [CDTrack]
            if let albumId = albumId {
                // Find album first
                let albumRequest: NSFetchRequest<CDAlbum> = CDAlbum.fetchRequest()
                albumRequest.predicate = NSPredicate(format: "id == %@ AND server == %@", albumId, cdServer)
                albumRequest.fetchLimit = 1
                guard let album = try context.fetch(albumRequest).first else {
                    self.logger.debug("Album \(albumId) not found in Core Data")
                    return [Track]()
                }
                
                // Use the album's tracks relationship directly (more efficient)
                if let tracksSet = album.tracks as? Set<CDTrack> {
                    cdTracks = Array(tracksSet)
                    self.logger.debug("Found \(cdTracks.count) tracks via relationship for album \(album.title ?? "Unknown")")
                } else {
                    // Fallback to fetch request if relationship isn't available
                    let trackRequest: NSFetchRequest<CDTrack> = CDTrack.fetchRequest()
                    trackRequest.predicate = NSPredicate(format: "album == %@ AND server == %@", album, cdServer)
                    trackRequest.sortDescriptors = [
                        NSSortDescriptor(key: "discNumber", ascending: true),
                        NSSortDescriptor(key: "trackNumber", ascending: true)
                    ]
                    cdTracks = try context.fetch(trackRequest)
                    self.logger.debug("Found \(cdTracks.count) tracks via fetch request for album \(album.title ?? "Unknown")")
                }
            } else {
                let trackRequest: NSFetchRequest<CDTrack> = CDTrack.fetchRequest()
                trackRequest.predicate = NSPredicate(format: "server == %@", cdServer)
                trackRequest.sortDescriptors = [NSSortDescriptor(key: "title", ascending: true)]
                cdTracks = try context.fetch(trackRequest)
            }
            
            // Sort CDTracks first (by disc number, then track number)
            // This ensures proper ordering whether we use relationship or fetch request
            let sortedCDTracks = cdTracks.sorted { track1, track2 in
                if track1.discNumber != track2.discNumber {
                    return track1.discNumber < track2.discNumber
                }
                return track1.trackNumber < track2.trackNumber
            }
            
            // Map to Track entities
            let tracks = sortedCDTracks.map { cdTrack in
                // Build stream URL for cached tracks so they're ready to play
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
            
            return tracks
        }
        
        // Only fall back to API if we got no results from Core Data
        // This ensures we use cached data when available
        if cachedTracks.isEmpty {
            self.logger.debug("No cached tracks found, fetching from API for album \(albumId ?? "all")")
            let dtos = try await apiClient.fetchTracks(byAlbumId: albumId)
            return dtos.map { dto in
                Track(dto: dto, serverId: serverId, apiClient: apiClient)
            }
        } else {
            self.logger.debug("Using \(cachedTracks.count) cached tracks for album \(albumId ?? "all")")
        }
        
        return cachedTracks
    }
    func fetchTracks(artistId: String?) async throws -> [Track] {
        // Try Core Data first
        let context = coreDataStack.viewContext
        let cachedTracks: [Track] = try await context.perform {
            let serverRequest: NSFetchRequest<CDServer> = CDServer.fetchRequest()
            serverRequest.predicate = NSPredicate(format: "id == %@", self.serverId as CVarArg)
            serverRequest.fetchLimit = 1
            guard let cdServer = try context.fetch(serverRequest).first else {
                self.logger.warning("Server not found in Core Data for artist tracks")
                return [Track]()
            }
            
            let cdTracks: [CDTrack]
            if let artistId = artistId {
                // Find artist first
                let artistRequest: NSFetchRequest<CDArtist> = CDArtist.fetchRequest()
                artistRequest.predicate = NSPredicate(format: "id == %@ AND server == %@", artistId, cdServer)
                artistRequest.fetchLimit = 1
                guard let artist = try context.fetch(artistRequest).first else {
                    self.logger.debug("Artist \(artistId) not found in Core Data")
                    return [Track]()
                }
                
                // Use the artist's tracks relationship directly (more efficient)
                if let tracksSet = artist.tracks as? Set<CDTrack> {
                    cdTracks = Array(tracksSet).filter { $0.server == cdServer }
                    self.logger.debug("Found \(cdTracks.count) tracks via relationship for artist \(artist.name ?? "Unknown")")
                } else {
                    // Fallback to fetch request if relationship isn't available
                    let trackRequest: NSFetchRequest<CDTrack> = CDTrack.fetchRequest()
                    trackRequest.predicate = NSPredicate(format: "artist == %@ AND server == %@", artist, cdServer)
                    trackRequest.sortDescriptors = [
                        NSSortDescriptor(key: "discNumber", ascending: true),
                        NSSortDescriptor(key: "trackNumber", ascending: true)
                    ]
                    cdTracks = try context.fetch(trackRequest)
                    self.logger.debug("Found \(cdTracks.count) tracks via fetch request for artist \(artist.name ?? "Unknown")")
                }
            } else {
                let trackRequest: NSFetchRequest<CDTrack> = CDTrack.fetchRequest()
                trackRequest.predicate = NSPredicate(format: "server == %@", cdServer)
                trackRequest.sortDescriptors = [NSSortDescriptor(key: "title", ascending: true)]
                cdTracks = try context.fetch(trackRequest)
            }
            
            // Map to Track entities
            let tracks = cdTracks.map { cdTrack in
                // Build stream URL for cached tracks so they're ready to play
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
            
            // Sort by album title, then disc number, then track number (in memory since we can't use dot notation)
            if artistId != nil {
                return tracks.sorted { track1, track2 in
                    let album1 = track1.albumTitle ?? ""
                    let album2 = track2.albumTitle ?? ""
                    if album1 != album2 {
                        return album1 < album2
                    }
                    let disc1 = track1.trackNumber ?? Int.max
                    let disc2 = track2.trackNumber ?? Int.max
                    return disc1 < disc2
                }
            }
            
            return tracks
        }
        
        // Only fall back to API if we got no results from Core Data
        // This ensures we use cached data when available
        if cachedTracks.isEmpty {
            self.logger.debug("No cached tracks found, fetching from API for artist \(artistId ?? "all")")
            let dtos = try await apiClient.fetchTracks(byArtistId: artistId)
            return dtos.map { dto in
                Track(dto: dto, serverId: serverId, apiClient: apiClient)
            }
        } else {
            self.logger.debug("Using \(cachedTracks.count) cached tracks for artist \(artistId ?? "all")")
        }
        
        return cachedTracks
    }
}
