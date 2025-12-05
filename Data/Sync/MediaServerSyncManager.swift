
import Foundation
@preconcurrency import CoreData

/// Sync progress information
struct SyncProgress {
    let progress: Double // 0.0 to 1.0
    let stage: String // Description of current stage
}

/// Manages full synchronization of library data from media server to Core Data
final class MediaServerSyncManager {
    private let apiClient: MediaServerAPIClient
    private let coreDataStack: CoreDataStack
    private let playlistSyncer: MediaServerPlaylistSyncer
    private let libraryFetcher: MediaServerLibraryFetcher
    private let libraryImporter: MediaServerLibraryImporter
    private let logger: AppLogger
    
    init(apiClient: MediaServerAPIClient, coreDataStack: CoreDataStack = .shared, logger: AppLogger = Log.make(.sync)) {
        self.apiClient = apiClient
        self.coreDataStack = coreDataStack
        self.logger = logger
        self.libraryFetcher = MediaServerLibraryFetcher(apiClient: apiClient, logger: logger)
        self.playlistSyncer = MediaServerPlaylistSyncer(apiClient: apiClient, coreDataStack: coreDataStack, logger: logger)
        self.libraryImporter = MediaServerLibraryImporter(apiClient: apiClient, coreDataStack: coreDataStack, logger: logger)
    }
    
    /// Performs a full sync of all library data for the given server
    /// - Parameters:
    ///   - server: The CDServer to sync
    ///   - progressCallback: Optional callback to report progress (0.0 to 1.0)
    /// - Throws: Errors from API calls or Core Data operations
    func performFullSync(
        for server: CDServer,
        progressCallback: @escaping (SyncProgress) -> Void = { _ in }
    ) async throws {
        logger.info("Starting full sync for server: \(server.name ?? "Unknown")")
        
        let (artists, albums, tracks) = try await libraryFetcher.fetchFullLibrary(
            progressCallback: progressCallback
        )
        
        try await libraryImporter.importLibrary(
            artists: artists,
            albums: albums,
            tracks: tracks,
            for: server,
            progressCallback: progressCallback
        )
        
        await MainActor.run {
            progressCallback(SyncProgress(progress: 0.99, stage: "Syncing playlists..."))
        }
        
        try await playlistSyncer.syncPlaylists(for: server, progressCallback: progressCallback)
        
        await MainActor.run {
            progressCallback(SyncProgress(progress: 1.0, stage: "Complete"))
        }
    }
    
    /// Syncs playlists from the media server to Core Data
    /// This is a convenience method that delegates to the playlist syncer
    func syncPlaylists(for server: CDServer) async throws {
        try await playlistSyncer.syncPlaylists(for: server)
    }
}

