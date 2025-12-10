
import Foundation
@preconcurrency import CoreData

/// Service for searching media in the library (used by Intents Extension)
/// This provides a simplified interface that can be used from the extension
final class MediaCatalogService {
    private let coreDataStack: CoreDataStack
    private let logger = Log.make(.siri)
    
    init(coreDataStack: CoreDataStack = .shared) {
        self.coreDataStack = coreDataStack
    }
    
    /// Get the active server ID from Core Data
    private func getActiveServerId() async -> UUID? {
        let context = coreDataStack.viewContext
        return await context.perform {
            let request: NSFetchRequest<CDServer> = CDServer.fetchRequest()
            // Get the most recently used server (you might want to add a lastUsedDate field)
            // For now, just get the first one
            request.fetchLimit = 1
            guard let server = try? context.fetch(request).first else {
                return nil
            }
            return server.id
        }
    }
    
    /// Search for artists by name
    func searchArtists(named name: String) async -> [Artist] {
        guard let serverId = await getActiveServerId() else {
            logger.warning("No active server found for search")
            return []
        }
        
        let context = coreDataStack.viewContext
        return await context.perform {
            let serverRequest: NSFetchRequest<CDServer> = CDServer.fetchRequest()
            serverRequest.predicate = NSPredicate(format: "id == %@", serverId as CVarArg)
            serverRequest.fetchLimit = 1
            guard let cdServer = try? context.fetch(serverRequest).first else {
                return []
            }
            
            let request: NSFetchRequest<CDArtist> = CDArtist.fetchRequest()
            request.predicate = NSPredicate(format: "server == %@ AND name CONTAINS[cd] %@", cdServer, name)
            request.sortDescriptors = [NSSortDescriptor(key: "sortName", ascending: true)]
            request.fetchLimit = 10 // Limit results for Siri
            
            guard let cdArtists = try? context.fetch(request) else {
                return []
            }
            
            return cdArtists.map { cdArtist in
                Artist(
                    id: cdArtist.id ?? "",
                    name: cdArtist.name ?? "",
                    thumbnailURL: cdArtist.imageURL.flatMap { URL(string: $0) }
                )
            }
        }
    }
    
    /// Search for albums by name (optionally by artist)
    func searchAlbums(named name: String, byArtist artistName: String?) async -> [Album] {
        guard let serverId = await getActiveServerId() else {
            return []
        }
        
        let context = coreDataStack.viewContext
        return await context.perform {
            let serverRequest: NSFetchRequest<CDServer> = CDServer.fetchRequest()
            serverRequest.predicate = NSPredicate(format: "id == %@", serverId as CVarArg)
            serverRequest.fetchLimit = 1
            guard let cdServer = try? context.fetch(serverRequest).first else {
                return []
            }
            
            let request: NSFetchRequest<CDAlbum> = CDAlbum.fetchRequest()
            var predicate: NSPredicate
            
            if let artistName = artistName {
                // Search for albums by this artist with matching name
                predicate = NSPredicate(format: "server == %@ AND title CONTAINS[cd] %@ AND artist.name CONTAINS[cd] %@", cdServer, name, artistName)
            } else {
                predicate = NSPredicate(format: "server == %@ AND title CONTAINS[cd] %@", cdServer, name)
            }
            
            request.predicate = predicate
            request.sortDescriptors = [NSSortDescriptor(key: "sortTitle", ascending: true)]
            request.fetchLimit = 10
            
            guard let cdAlbums = try? context.fetch(request) else {
                return []
            }
            
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
    }
    
    /// Search for tracks by name (optionally by artist)
    func searchTracks(named name: String, byArtist artistName: String?) async -> [Track] {
        guard let serverId = await getActiveServerId() else {
            return []
        }
        
        let context = coreDataStack.viewContext
        return await context.perform {
            let serverRequest: NSFetchRequest<CDServer> = CDServer.fetchRequest()
            serverRequest.predicate = NSPredicate(format: "id == %@", serverId as CVarArg)
            serverRequest.fetchLimit = 1
            guard let cdServer = try? context.fetch(serverRequest).first else {
                return []
            }
            
            let request: NSFetchRequest<CDTrack> = CDTrack.fetchRequest()
            var predicate: NSPredicate
            
            if let artistName = artistName {
                predicate = NSPredicate(format: "server == %@ AND title CONTAINS[cd] %@ AND artist.name CONTAINS[cd] %@", cdServer, name, artistName)
            } else {
                predicate = NSPredicate(format: "server == %@ AND (title CONTAINS[cd] %@ OR artist.name CONTAINS[cd] %@)", cdServer, name, name)
            }
            
            request.predicate = predicate
            request.sortDescriptors = [NSSortDescriptor(key: "title", ascending: true)]
            request.fetchLimit = 10
            
            guard let cdTracks = try? context.fetch(request) else {
                return []
            }
            
            return cdTracks.map { cdTrack in
                Track(
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
                    streamUrl: nil,
                    serverId: serverId
                )
            }
        }
    }
    
    /// Find a track by its ID
    func findTrack(byId trackId: String) async -> Track? {
        guard let serverId = await getActiveServerId() else {
            return nil
        }
        
        let context = coreDataStack.viewContext
        return await context.perform {
            let serverRequest: NSFetchRequest<CDServer> = CDServer.fetchRequest()
            serverRequest.predicate = NSPredicate(format: "id == %@", serverId as CVarArg)
            serverRequest.fetchLimit = 1
            guard let cdServer = try? context.fetch(serverRequest).first else {
                return nil
            }
            
            let request: NSFetchRequest<CDTrack> = CDTrack.fetchRequest()
            request.predicate = NSPredicate(format: "id == %@ AND server == %@", trackId, cdServer)
            request.fetchLimit = 1
            
            guard let cdTrack = try? context.fetch(request).first else {
                return nil
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
                streamUrl: nil,
                serverId: serverId
            )
        }
    }
    
    /// Search for playlists by name
    func searchPlaylists(named name: String) async -> [Playlist] {
        guard let serverId = await getActiveServerId() else {
            return []
        }
        
        let context = coreDataStack.viewContext
        return await context.perform {
            let serverRequest: NSFetchRequest<CDServer> = CDServer.fetchRequest()
            serverRequest.predicate = NSPredicate(format: "id == %@", serverId as CVarArg)
            serverRequest.fetchLimit = 1
            guard let cdServer = try? context.fetch(serverRequest).first else {
                return []
            }
            
            let request: NSFetchRequest<CDPlaylist> = CDPlaylist.fetchRequest()
            request.predicate = NSPredicate(format: "server == %@ AND name CONTAINS[cd] %@", cdServer, name)
            request.sortDescriptors = [NSSortDescriptor(key: "name", ascending: true)]
            request.fetchLimit = 10
            
            guard let cdPlaylists = try? context.fetch(request) else {
                return []
            }
            
            return cdPlaylists.map { cdPlaylist in
                Playlist(
                    id: cdPlaylist.id ?? "",
                    name: cdPlaylist.name ?? "",
                    summary: cdPlaylist.summary,
                    isSmart: cdPlaylist.isSmart,
                    source: .jellyfin,
                    isReadOnly: cdPlaylist.isReadOnly,
                    createdAt: cdPlaylist.createdAt,
                    updatedAt: cdPlaylist.updatedAt
                )
            }
        }
    }
}

