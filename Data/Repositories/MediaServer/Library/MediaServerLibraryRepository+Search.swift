
import Foundation
@preconcurrency import CoreData

extension MediaServerLibraryRepository {
    func search(query: String) async throws -> [Track] {
        // Search in Core Data
        let context = coreDataStack.viewContext
        return try await context.perform {
            let serverRequest: NSFetchRequest<CDServer> = CDServer.fetchRequest()
            serverRequest.predicate = NSPredicate(format: "id == %@", self.serverId as CVarArg)
            serverRequest.fetchLimit = 1
            guard let cdServer = try context.fetch(serverRequest).first else {
                self.logger.error("Server not found in Core Data for search (serverId: \(self.serverId))")
                throw LibraryRepositoryError.serverNotFound
            }
            
            let request: NSFetchRequest<CDTrack> = CDTrack.fetchRequest()
            request.predicate = NSPredicate(format: "server == %@ AND (title CONTAINS[cd] %@ OR artist.name CONTAINS[cd] %@)", cdServer, query, query)
            request.sortDescriptors = [NSSortDescriptor(key: "title", ascending: true)]
            
            let cdTracks = try context.fetch(request)
            if !cdTracks.isEmpty {
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
                        serverId: self.serverId
                    )
                }
            }
            
            // Fall back to API (not implemented yet)
            return []
        }
    }
    
    func searchAll(query: String) async throws -> SearchResults {
        // Search in Core Data across tracks, albums, and artists
        let context = coreDataStack.viewContext
        return try await context.perform {
            let serverRequest: NSFetchRequest<CDServer> = CDServer.fetchRequest()
            serverRequest.predicate = NSPredicate(format: "id == %@", self.serverId as CVarArg)
            serverRequest.fetchLimit = 1
            guard let cdServer = try context.fetch(serverRequest).first else {
                self.logger.error("Server not found in Core Data for search (serverId: \(self.serverId))")
                throw LibraryRepositoryError.serverNotFound
            }
            
            // Search tracks
            let trackRequest: NSFetchRequest<CDTrack> = CDTrack.fetchRequest()
            trackRequest.predicate = NSPredicate(format: "server == %@ AND (title CONTAINS[cd] %@ OR artist.name CONTAINS[cd] %@ OR album.title CONTAINS[cd] %@)", cdServer, query, query, query)
            trackRequest.sortDescriptors = [NSSortDescriptor(key: "title", ascending: true)]
            let cdTracks = try context.fetch(trackRequest)
            let tracks = cdTracks.map { cdTrack in
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
                    serverId: self.serverId
                )
            }
            
            // Search albums
            let albumRequest: NSFetchRequest<CDAlbum> = CDAlbum.fetchRequest()
            albumRequest.predicate = NSPredicate(format: "server == %@ AND (title CONTAINS[cd] %@ OR artist.name CONTAINS[cd] %@)", cdServer, query, query)
            albumRequest.sortDescriptors = [NSSortDescriptor(key: "sortTitle", ascending: true)]
            let cdAlbums = try context.fetch(albumRequest)
            let albums = cdAlbums.map { cdAlbum in
                Album(
                    id: cdAlbum.id ?? "",
                    title: cdAlbum.title ?? "",
                    artistName: cdAlbum.artist?.name ?? "Unknown Artist",
                    thumbnailURL: cdAlbum.imageURL.flatMap { URL(string: $0) },
                    year: cdAlbum.year > 0 ? Int(cdAlbum.year) : nil
                )
            }
            
            // Search artists
            let artistRequest: NSFetchRequest<CDArtist> = CDArtist.fetchRequest()
            artistRequest.predicate = NSPredicate(format: "server == %@ AND name CONTAINS[cd] %@", cdServer, query)
            artistRequest.sortDescriptors = [NSSortDescriptor(key: "sortName", ascending: true)]
            let cdArtists = try context.fetch(artistRequest)
            let artists = cdArtists.map { cdArtist in
                Artist(
                    id: cdArtist.id ?? "",
                    name: cdArtist.name ?? "",
                    thumbnailURL: cdArtist.imageURL.flatMap { URL(string: $0) }
                )
            }
            
            return SearchResults(tracks: tracks, albums: albums, artists: artists)
        }
    }
}

