
import Foundation
import CoreData

// MARK: - Server Extensions

extension CDServer {
    var serverType: MediaServerType {
        get {
            if let typeRaw = typeRaw, let type = MediaServerType(rawValue: typeRaw) {
                return type
            }
            return .jellyfin
        }
        set {
            typeRaw = newValue.rawValue
        }
    }
    
    func toDomain() -> Server {
        Server(
            id: id ?? UUID(),
            name: name ?? "",
            baseURL: URL(string: baseURL ?? "") ?? URL(string: "https://example.com")!,
            username: username ?? "",
            userId: userId ?? "",
            accessToken: accessToken ?? "",
            serverType: serverType
        )
    }
    
    static func fromDomain(_ server: Server, in context: NSManagedObjectContext) -> CDServer {
        let cdServer = CDServer(context: context)
        cdServer.id = server.id
        cdServer.name = server.name
        cdServer.baseURL = server.baseURL.absoluteString
        cdServer.username = server.username
        cdServer.userId = server.userId
        cdServer.accessToken = server.accessToken
        cdServer.serverType = server.serverType
        cdServer.isActive = false // Will be set separately
        return cdServer
    }
    
    static func fetchActive(in context: NSManagedObjectContext) throws -> CDServer? {
        let request: NSFetchRequest<CDServer> = CDServer.fetchRequest()
        request.predicate = NSPredicate(format: "isActive == YES")
        request.fetchLimit = 1
        return try context.fetch(request).first
    }
    
    static func fetchAll(in context: NSManagedObjectContext) throws -> [CDServer] {
        let request: NSFetchRequest<CDServer> = CDServer.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(key: "name", ascending: true)]
        return try context.fetch(request)
    }
    
    static func findBy(id: UUID, in context: NSManagedObjectContext) throws -> CDServer? {
        let request: NSFetchRequest<CDServer> = CDServer.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        request.fetchLimit = 1
        return try context.fetch(request).first
    }
}

// MARK: - Artist Extensions

extension CDArtist {
    #if !INTENTS_EXTENSION
    static func upsert(from dto: JellyfinArtistDTO, server: CDServer, apiClient: MediaServerAPIClient, in context: NSManagedObjectContext) -> CDArtist {
        let request: NSFetchRequest<CDArtist> = CDArtist.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@ AND server == %@", dto.id, server)
        request.fetchLimit = 1
        
        let cdArtist = (try? context.fetch(request).first) ?? CDArtist(context: context)
        
        cdArtist.id = dto.id
        cdArtist.name = dto.name
        cdArtist.sortName = dto.name // Jellyfin doesn't always provide SortName in this endpoint
        cdArtist.imageTagPrimary = dto.primaryImageTag
        
        cdArtist.imageURL = apiClient.buildImageURL(
            forItemId: dto.id,
            imageType: "Primary",
            maxWidth: 300,
            tag: dto.primaryImageTag
        )?.absoluteString
        
        cdArtist.server = server
        
        return cdArtist
    }
    #endif
    
    func toDomain() -> Artist {
        Artist(
            id: id ?? "",
            name: name ?? "",
            thumbnailURL: imageURL.flatMap { URL(string: $0) }
        )
    }
}

// MARK: - Album Extensions

extension CDAlbum {
    #if !INTENTS_EXTENSION
    static func upsert(from dto: JellyfinAlbumDTO, artist: CDArtist?, server: CDServer, apiClient: MediaServerAPIClient, in context: NSManagedObjectContext) -> CDAlbum {
        // Find existing or create new
        let request: NSFetchRequest<CDAlbum> = CDAlbum.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@ AND server == %@", dto.id, server)
        request.fetchLimit = 1
        
        let cdAlbum = (try? context.fetch(request).first) ?? CDAlbum(context: context)
        
        // Update attributes
        cdAlbum.id = dto.id
        cdAlbum.title = dto.name
        cdAlbum.sortTitle = dto.name // Jellyfin doesn't always provide SortName
        cdAlbum.year = Int16(dto.productionYear ?? 0)
        cdAlbum.imageTagPrimary = dto.primaryImageTag
        cdAlbum.isFavorite = false // Will be updated from user data if available
        
        // Build image URL - try with tag if available, otherwise try without (Emby may have images even without ImageTags)
        // Check for both "Primary" and "primary" keys (case-insensitive handling)
        // Also try "Thumb" or any other available tag as fallback
        var imageTag: String? = dto.primaryImageTag
        var imageType = "Primary"
        
        if imageTag == nil || imageTag!.isEmpty {
            // Try "Thumb" as fallback
            imageTag = dto.imageTags?["Thumb"] ?? dto.imageTags?["thumb"]
            if imageTag != nil && !imageTag!.isEmpty {
                imageType = "Thumb"
            } else {
                // Try any available tag
                imageTag = dto.imageTags?.values.first
                if imageTag != nil && !imageTag!.isEmpty {
                    // Use the first available image type
                    imageType = dto.imageTags?.keys.first ?? "Primary"
                }
            }
        }
        
        // Use the new buildImageURL with tag parameter (handles server-specific quirks internally)
        cdAlbum.imageURL = apiClient.buildImageURL(
            forItemId: dto.id,
            imageType: imageType,
            maxWidth: 300,
            tag: imageTag
        )?.absoluteString
        
        // Set relationships
        cdAlbum.artist = artist
        cdAlbum.server = server
        
        return cdAlbum
    }
    #endif
    
    func toDomain() -> Album {
        Album(
            id: id ?? "",
            title: title ?? "",
            artistName: artist?.name ?? "Unknown Artist",
            thumbnailURL: imageURL.flatMap { URL(string: $0) },
            year: year > 0 ? Int(year) : nil
        )
    }
}

// MARK: - Genre Extensions

extension CDGenre {
    #if !INTENTS_EXTENSION
    static func upsert(rawName: String, server: CDServer, in context: NSManagedObjectContext) -> CDGenre {
        // Normalize the genre name for lookup
        let normalized = UmbrellaGenres.normalize(rawName)
        
        // Find existing by normalized name
        let request: NSFetchRequest<CDGenre> = CDGenre.fetchRequest()
        request.predicate = NSPredicate(format: "normalizedName == %@ AND server == %@", normalized, server)
        request.fetchLimit = 1
        
        let cdGenre = (try? context.fetch(request).first) ?? CDGenre(context: context)
        
        // Update attributes
        cdGenre.rawName = rawName
        cdGenre.normalizedName = normalized
        cdGenre.umbrellaName = UmbrellaGenres.resolve(rawName)
        cdGenre.server = server
        
        return cdGenre
    }
    #endif
}

// MARK: - Track Extensions

extension CDTrack {
    #if !INTENTS_EXTENSION
    private static let logger = Log.make(.storage)
    
    static func upsert(from dto: JellyfinTrackDTO, album: CDAlbum?, artist: CDArtist?, genres: Set<CDGenre>, server: CDServer, existingTrack: CDTrack? = nil, in context: NSManagedObjectContext) -> CDTrack {
        // Use provided existing track, or fetch if not provided
        let cdTrack: CDTrack
        if let existing = existingTrack {
            cdTrack = existing
            // Only log for new tracks to reduce log noise
        } else {
            // Fallback: fetch if not provided (for backward compatibility)
            let request: NSFetchRequest<CDTrack> = CDTrack.fetchRequest()
            request.predicate = NSPredicate(format: "id == %@ AND server == %@", dto.id, server)
            request.fetchLimit = 1
            
            if let fetched = try? context.fetch(request).first {
                cdTrack = fetched
            } else {
                cdTrack = CDTrack(context: context)
                Self.logger.debug("CDTrack.upsert - Track DOES NOT EXIST - Creating new - ID: \(dto.id), Title: \(dto.name)")
            }
        }
        
        // Update attributes
        cdTrack.id = dto.id
        cdTrack.title = dto.name
        cdTrack.duration = {
            let ticks = dto.runTimeTicks ?? 0
            if ticks > 0 {
                let calculated = TimeInterval(ticks) / 10_000_000.0
                if calculated.isNaN || calculated.isInfinite {
                    return 0
                }
                return calculated
            }
            return 0
        }()
        cdTrack.trackNumber = Int16(dto.indexNumber ?? 0)
        cdTrack.discNumber = Int16(dto.discNumber ?? 0)
        cdTrack.isLiked = dto.userData?.isFavorite ?? false
        cdTrack.playCount = Int32(dto.playCount ?? 0)
        cdTrack.container = dto.container
        
        // Parse dateAdded (Jellyfin uses ISO8601 format)
        if let dateString = dto.dateAdded, !dateString.isEmpty {
            let formatter = ISO8601DateFormatter()
            // Try with fractional seconds first
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            var date = formatter.date(from: dateString)
            
            // If that fails, try without fractional seconds
            if date == nil {
                formatter.formatOptions = [.withInternetDateTime]
                date = formatter.date(from: dateString)
            }
            
            cdTrack.dateAdded = date
        }
        
        // Store genre arrays for quick access
        let genreNames = dto.genres ?? []
        let classification = UmbrellaGenres.classifyGenres(genreNames)
        // If no genres, set "Unknown" as the umbrella genre
        let rawGenres = classification.raw.isEmpty ? [] : classification.raw
        let normalizedGenres = classification.normalized.isEmpty ? [] : classification.normalized
        let umbrellaGenres = classification.umbrella.isEmpty ? ["Unknown"] : classification.umbrella
        cdTrack.rawGenres = rawGenres as NSArray
        cdTrack.normalizedGenres = normalizedGenres as NSArray
        cdTrack.umbrellaGenres = umbrellaGenres as NSArray
        
        // Set relationships
        cdTrack.album = album
        cdTrack.artist = artist
        // If no genres provided, ensure "Unknown" genre is included
        var finalGenres = genres
        if genres.isEmpty {
            // Try to find or create "Unknown" genre
            let unknownNormalized = UmbrellaGenres.normalize("Unknown")
            let request: NSFetchRequest<CDGenre> = CDGenre.fetchRequest()
            request.predicate = NSPredicate(format: "normalizedName == %@ AND server == %@", unknownNormalized, server)
            request.fetchLimit = 1
            if let unknownGenre = try? context.fetch(request).first {
                finalGenres.insert(unknownGenre)
            } else {
                // Create "Unknown" genre if it doesn't exist
                let unknownGenre = CDGenre.upsert(rawName: "Unknown", server: server, in: context)
                finalGenres.insert(unknownGenre)
            }
        }
        cdTrack.genres = NSSet(set: finalGenres)
        cdTrack.server = server
        
        return cdTrack
    }
    #endif
    
    func toDomain(serverId: UUID) -> Track {
        // Map from relationships to flat structure for UI compatibility
        Track(
            id: id ?? "",
            title: title ?? "",
            albumId: album?.id,
            albumTitle: album?.title,
            artistName: artist?.name ?? "Unknown Artist",
            duration: duration,
            trackNumber: trackNumber > 0 ? Int(trackNumber) : nil,
            discNumber: discNumber > 0 ? Int(discNumber) : nil,
            dateAdded: dateAdded,
            playCount: Int(playCount),
            isLiked: isLiked,
            streamUrl: nil, // Will be built when needed
            serverId: serverId
        )
    }
    
    #if !INTENTS_EXTENSION
    static func findBy(id: String, server: CDServer, in context: NSManagedObjectContext) throws -> CDTrack? {
        let request: NSFetchRequest<CDTrack> = CDTrack.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@ AND server == %@", id, server)
        request.fetchLimit = 1
        let result = try context.fetch(request).first
        if let track = result {
            Self.logger.debug("CDTrack.findBy - Track EXISTS - ID: \(id), Title: \(track.title ?? "Unknown")")
        } else {
            Self.logger.debug("CDTrack.findBy - Track DOES NOT EXIST - ID: \(id)")
        }
        return result
    }
    
    /// Deletes a track by ID from Core Data
    /// - Parameters:
    ///   - id: The track ID to delete
    ///   - context: The managed object context
    /// - Throws: Core Data errors if fetch or save fails
    static func deleteById(_ id: String, in context: NSManagedObjectContext) throws {
        let request: NSFetchRequest<CDTrack> = CDTrack.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", id)
        request.fetchLimit = 1
        
        if let track = try context.fetch(request).first {
            context.delete(track)
            try context.save()
        }
    }
    #endif
    
    static func fetchAll(server: CDServer, in context: NSManagedObjectContext) throws -> [CDTrack] {
        let request: NSFetchRequest<CDTrack> = CDTrack.fetchRequest()
        request.predicate = NSPredicate(format: "server == %@", server)
        request.sortDescriptors = [NSSortDescriptor(key: "title", ascending: true)]
        return try context.fetch(request)
    }
    
    static func fetchByAlbum(_ album: CDAlbum, in context: NSManagedObjectContext) throws -> [CDTrack] {
        let request: NSFetchRequest<CDTrack> = CDTrack.fetchRequest()
        request.predicate = NSPredicate(format: "album == %@", album)
        request.sortDescriptors = [
            NSSortDescriptor(key: "discNumber", ascending: true),
            NSSortDescriptor(key: "trackNumber", ascending: true)
        ]
        return try context.fetch(request)
    }
}
