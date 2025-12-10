
import Foundation
@preconcurrency import CoreData

/// Sync progress information
struct SyncProgress: Sendable {
    let progress: Double // 0.0 to 1.0
    let stage: String // Description of current stage
}

/// Sync error types
enum SyncError: Error, Sendable {
    case alreadySyncing
    case cancelled
}

/// Manages full synchronization of library data from media server to Core Data
/// Serialized as an actor to prevent concurrent syncs
actor MediaServerSyncManager {
    private let apiClient: MediaServerAPIClient
    private let coreDataStack: CoreDataStack
    nonisolated private let logger: AppLogger
    
    // Track sync state per server
    private var isSyncing: [UUID: Bool] = [:]
    private var currentSyncTask: [UUID: Task<Void, Error>] = [:]

    init(apiClient: MediaServerAPIClient, coreDataStack: CoreDataStack, logger: AppLogger) {
        self.apiClient = apiClient
        self.coreDataStack = coreDataStack
        self.logger = logger
    }
    
    /// Factory method with defaults (can be called from any context)
    static func create(apiClient: MediaServerAPIClient, coreDataStack: CoreDataStack = CoreDataStack.shared, logger: AppLogger = Log.make(.sync)) -> MediaServerSyncManager {
        return MediaServerSyncManager(apiClient: apiClient, coreDataStack: coreDataStack, logger: logger)
    }
    
    /// Performs a full sync of all library data for the given server
    /// - Parameters:
    ///   - server: The CDServer to sync
    ///   - progressCallback: Optional callback to report progress (0.0 to 1.0)
    /// - Throws: Errors from API calls or Core Data operations, or SyncError if already syncing
    func performFullSync(
        for server: CDServer,
        progressCallback: @Sendable @escaping (SyncProgress) -> Void = { _ in }
    ) async throws {
        // Extract objectID first (it's Sendable) to avoid capturing non-Sendable CDServer
        let serverObjectID = server.objectID
        
        // Extract server properties on main actor using objectID
        let (serverId, serverName) = await MainActor.run {
            let context = coreDataStack.viewContext
            guard let serverInContext = try? context.existingObject(with: serverObjectID) as? CDServer else {
                return (nil as UUID?, "Unknown")
            }
            return (serverInContext.id, serverInContext.name ?? "Unknown")
        }
        
        // Validate server ID
        guard let serverId = serverId else {
            logger.warning("Sync failed: Server has no ID")
            throw SyncError.alreadySyncing // Reuse error type for invalid server
        }
        
        // Check if already syncing
        if isSyncing[serverId] == true {
            logger.warning("Sync already in progress for server \(serverName), ignoring duplicate request")
            throw SyncError.alreadySyncing
        }
        
        // Cancel any existing sync task for this server
        if let existingTask = currentSyncTask[serverId] {
            existingTask.cancel()
            currentSyncTask[serverId] = nil
        }
        
        // Mark as syncing
        isSyncing[serverId] = true
        
        // Create sync task with proper type that can throw errors
        let capturedObjectID = serverObjectID
        let capturedServerName = serverName
        let capturedApiClient = apiClient
        let capturedCoreDataStack = coreDataStack
        let capturedLogger = logger
        let syncTask = Task<Void, Error> {
            try await MediaServerSyncManager.executeFullSync(
                serverObjectID: capturedObjectID,
                serverName: capturedServerName,
                apiClient: capturedApiClient,
                coreDataStack: capturedCoreDataStack,
                logger: capturedLogger,
                progressCallback: progressCallback
            )
        }
        
        currentSyncTask[serverId] = syncTask

        // Wait for sync to complete and propagate errors
        do {
            try await syncTask.value
            markSyncComplete(serverId: serverId)
        } catch is CancellationError {
            markSyncComplete(serverId: serverId)
            logger.info("Sync cancelled for server: \(serverName)")
            throw SyncError.cancelled
        } catch {
            markSyncComplete(serverId: serverId)
            logger.error("Sync failed for server \(serverName): \(error.localizedDescription)")
            throw error
        }
    }

    /// Mark sync as complete
    private func markSyncComplete(serverId: UUID) {
        isSyncing[serverId] = false
        currentSyncTask[serverId] = nil
    }
    
    /// Cancel sync for a server
    func cancelSync(for serverId: UUID) {
        if let task = currentSyncTask[serverId] {
            task.cancel()
            currentSyncTask[serverId] = nil
            isSyncing[serverId] = false
            // Logger is nonisolated, can be called from actor context
            logger.info("Cancelled sync for server ID: \(serverId)")
        }
    }
    
    /// Check if a server is currently syncing
    func isSyncing(serverId: UUID) -> Bool {
        return isSyncing[serverId] == true
    }
    
    /// Syncs playlists from the media server to Core Data
    /// This is a convenience method that delegates to the playlist syncer
    func syncPlaylists(for serverObjectID: NSManagedObjectID) async throws {
        try await MediaServerPlaylistSyncer.syncPlaylists(
            for: serverObjectID,
            apiClient: apiClient,
            coreDataStack: coreDataStack,
            logger: logger
        )
    }

    /// Performs the actual synchronization work on the actor
    private static func executeFullSync(
        serverObjectID: NSManagedObjectID,
        serverName: String,
        apiClient: MediaServerAPIClient,
        coreDataStack: CoreDataStack,
        logger: AppLogger,
        progressCallback: @Sendable @escaping (SyncProgress) -> Void
    ) async throws {
        logger.info("Starting full sync for server: \(serverName)")
        
        let (artists, albums, tracks) = try await MediaServerLibraryFetcher.fetchFullLibrary(
            apiClient: apiClient,
            logger: logger,
            progressCallback: progressCallback
        )
        
        try Task.checkCancellation()
        
        try await MediaServerLibraryImporter.importLibrary(
            artists: artists,
            albums: albums,
            tracks: tracks,
            serverObjectID: serverObjectID,
            apiClient: apiClient,
            coreDataStack: coreDataStack,
            logger: logger,
            progressCallback: progressCallback
        )
        
        try Task.checkCancellation()
        
        await MainActor.run {
            progressCallback(SyncProgress(progress: 0.99, stage: "Syncing playlists..."))
        }
        
        try await MediaServerPlaylistSyncer.syncPlaylists(
            for: serverObjectID,
            apiClient: apiClient,
            coreDataStack: coreDataStack,
            logger: logger,
            progressCallback: progressCallback
        )
        
        await MainActor.run {
            progressCallback(SyncProgress(progress: 1.0, stage: "Complete"))
        }
        
        logger.info("Full sync completed for server: \(serverName)")
    }
}
