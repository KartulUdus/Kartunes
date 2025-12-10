
import Foundation
@preconcurrency import CoreData

/// Bundles existing library state for efficient bulk operations
struct ExistingLibraryState {
    let artists: [String: CDArtist]
    let albums: [String: CDAlbum]
    let tracks: [String: CDTrack]
    let genres: [String: CDGenre]
}

/// Handles importing library data into Core Data
final class MediaServerLibraryImporter {
    nonisolated private let apiClient: MediaServerAPIClient
    nonisolated private let coreDataStack: CoreDataStack
    nonisolated private let logger: AppLogger
    
    nonisolated init(apiClient: MediaServerAPIClient, coreDataStack: CoreDataStack, logger: AppLogger) {
        self.apiClient = apiClient
        self.coreDataStack = coreDataStack
        self.logger = logger
    }
    
    /// Imports library data (artists, albums, tracks) into Core Data
    func importLibrary(
        artists: [JellyfinArtistDTO],
        albums: [JellyfinAlbumDTO],
        tracks: [JellyfinTrackDTO],
        for server: CDServer,
        progressCallback: @escaping (SyncProgress) -> Void
    ) async throws {
        let context = coreDataStack.newBackgroundContext()
        let serverObjectID = server.objectID
        
        try await context.perform {
            let serverInContext = try context.existingObject(with: serverObjectID) as! CDServer
            
            let remoteArtistIds = Set(artists.map { $0.id })
            let remoteAlbumIds = Set(albums.map { $0.id })
            let remoteTrackIds = Set(tracks.map { $0.id })
            
            self.logger.debug("Starting bulk sync - Remote: \(remoteArtistIds.count) artists, \(remoteAlbumIds.count) albums, \(remoteTrackIds.count) tracks")
            
            DispatchQueue.main.async {
                progressCallback(SyncProgress(progress: 0.50, stage: "Loading existing data..."))
            }
            
            let state = try self.fetchExistingLibraryState(
                for: serverInContext,
                in: context
            )
            
            let artistMap = ArtistSyncPhase.upsertArtists(
                from: artists,
                in: context,
                server: serverInContext,
                apiClient: self.apiClient,
                existing: state.artists,
                progressCallback: progressCallback
            )
            
            let albumMap = AlbumSyncPhase.upsertAlbums(
                from: albums,
                artists: artistMap,
                in: context,
                server: serverInContext,
                apiClient: self.apiClient,
                existing: state.albums,
                progressCallback: progressCallback,
                logger: self.logger
            )
            
            let genreMap = GenreSyncPhase.upsertGenres(
                from: tracks,
                existing: state.genres,
                server: serverInContext,
                in: context
            )
            
            TrackSyncPhase.upsertTracks(
                from: tracks,
                albums: albumMap,
                artists: artistMap,
                genres: genreMap,
                existingTracks: state.tracks,
                server: serverInContext,
                in: context,
                progressCallback: progressCallback,
                logger: self.logger
            )
            
            CleanupPhase.removeDeletedEntities(
                state: state,
                remoteArtistIDs: remoteArtistIds,
                remoteAlbumIDs: remoteAlbumIds,
                remoteTrackIDs: remoteTrackIds,
                in: context,
                logger: self.logger
            )
            
            serverInContext.lastFullSync = Date()
            
            DispatchQueue.main.async {
                progressCallback(SyncProgress(progress: 0.98, stage: "Processing library..."))
            }
            
            try context.save()
            
            self.logger.info("Full sync completed successfully")
            let trackCount = try context.fetch(NSFetchRequest<CDTrack>(entityName: "CDTrack")).count
            self.logger.debug("Library sync finished. Total tracks in Core Data: \(trackCount)")
        }
    }
    
    /// Fetches all existing library entities for the server
    private func fetchExistingLibraryState(
        for server: CDServer,
        in context: NSManagedObjectContext
    ) throws -> ExistingLibraryState {
        // Fetch all existing artists for this server
        let existingArtistsRequest: NSFetchRequest<CDArtist> = CDArtist.fetchRequest()
        existingArtistsRequest.predicate = NSPredicate(format: "server == %@", server)
        let existingArtists = try context.fetch(existingArtistsRequest)
        var existingArtistMap: [String: CDArtist] = [:]
        for artist in existingArtists {
            if let id = artist.id {
                existingArtistMap[id] = artist
            }
        }
        logger.debug("Found \(existingArtists.count) existing artists in Core Data")
        
        let existingAlbumsRequest: NSFetchRequest<CDAlbum> = CDAlbum.fetchRequest()
        existingAlbumsRequest.predicate = NSPredicate(format: "server == %@", server)
        let existingAlbums = try context.fetch(existingAlbumsRequest)
        var existingAlbumMap: [String: CDAlbum] = [:]
        for album in existingAlbums {
            if let id = album.id {
                existingAlbumMap[id] = album
            }
        }
        logger.debug("Found \(existingAlbums.count) existing albums in Core Data")
        
        let existingTracksRequest: NSFetchRequest<CDTrack> = CDTrack.fetchRequest()
        existingTracksRequest.predicate = NSPredicate(format: "server == %@", server)
        let existingTracks = try context.fetch(existingTracksRequest)
        var existingTrackMap: [String: CDTrack] = [:]
        for track in existingTracks {
            if let id = track.id {
                existingTrackMap[id] = track
            }
        }
        logger.debug("Found \(existingTracks.count) existing tracks in Core Data")
        
        let existingGenresRequest: NSFetchRequest<CDGenre> = CDGenre.fetchRequest()
        existingGenresRequest.predicate = NSPredicate(format: "server == %@", server)
        let existingGenres = try context.fetch(existingGenresRequest)
        var existingGenreMap: [String: CDGenre] = [:]
        for genre in existingGenres {
            if let normalized = genre.normalizedName {
                existingGenreMap[normalized] = genre
            }
        }
        logger.debug("Found \(existingGenres.count) existing genres in Core Data")
        
        return ExistingLibraryState(
            artists: existingArtistMap,
            albums: existingAlbumMap,
            tracks: existingTrackMap,
            genres: existingGenreMap
        )
    }
}

