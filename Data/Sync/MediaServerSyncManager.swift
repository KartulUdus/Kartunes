
import Foundation
@preconcurrency import CoreData

/// Sync progress information
struct SyncProgress {
    let progress: Double // 0.0 to 1.0
    let stage: String // Description of current stage
}

/// Sync error types
enum SyncError: Error {
    case alreadySyncing
    case cancelled
}

/// Manages full synchronization of library data from media server to Core Data
/// Serialized as an actor to prevent concurrent syncs
actor MediaServerSyncManager {
    private let apiClient: MediaServerAPIClient
    private let coreDataStack: CoreDataStack
    private let playlistSyncer: MediaServerPlaylistSyncer
    private let libraryFetcher: MediaServerLibraryFetcher
    private let libraryImporter: MediaServerLibraryImporter
    nonisolated private let logger: AppLogger
    
    // Track sync state per server
    private var isSyncing: [UUID: Bool] = [:]
    private var currentSyncTask: [UUID: Task<Void, Error>] = [:]
    
    init(apiClient: MediaServerAPIClient, coreDataStack: CoreDataStack, logger: AppLogger) {
        self.apiClient = apiClient
        self.coreDataStack = coreDataStack
        self.logger = logger
        // Create helpers with explicit logger (no default parameter calls)
        // These are value types/classes with nonisolated initializers
        self.libraryFetcher = MediaServerLibraryFetcher(apiClient: apiClient, logger: logger)
        self.playlistSyncer = MediaServerPlaylistSyncer(apiClient: apiClient, coreDataStack: coreDataStack, logger: logger)
        self.libraryImporter = MediaServerLibraryImporter(apiClient: apiClient, coreDataStack: coreDataStack, logger: logger)
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
        progressCallback: @escaping (SyncProgress) -> Void = { _ in }
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
        // Capture all needed values explicitly to avoid actor isolation issues
        let capturedObjectID = serverObjectID
        let capturedCoreDataStack = coreDataStack
        let capturedLogger = logger
        let capturedLibraryFetcher = libraryFetcher
        let capturedLibraryImporter = libraryImporter
        let capturedPlaylistSyncer = playlistSyncer
        let capturedServerName = serverName
        let capturedServerId = serverId
        let syncTask = Task<Void, Error> { @Sendable in
            defer {
                Task { @MainActor in
                    await self.markSyncComplete(serverId: capturedServerId)
                }
            }
            
            capturedLogger.info("Starting full sync for server: \(capturedServerName)")
            
            let (artists, albums, tracks) = try await capturedLibraryFetcher.fetchFullLibrary(
                progressCallback: progressCallback
            )
            
            // Check for cancellation
            try Task.checkCancellation()
            
            // Get server from main context for import
            // importLibrary will extract objectID and get server in background context
            // CDServer is non-Sendable but safe here (thread-confined to main context)
            nonisolated(unsafe) let serverForImport = await MainActor.run {
                let context = capturedCoreDataStack.viewContext
                return try! context.existingObject(with: capturedObjectID) as! CDServer
            }
            try await capturedLibraryImporter.importLibrary(
                artists: artists,
                albums: albums,
                tracks: tracks,
                for: serverForImport,
                progressCallback: progressCallback
            )
            
            // Check for cancellation
            try Task.checkCancellation()
            
            await MainActor.run {
                progressCallback(SyncProgress(progress: 0.99, stage: "Syncing playlists..."))
            }
            
            // Get server for playlist sync
            // CDServer is non-Sendable but safe here (thread-confined to main context)
            nonisolated(unsafe) let serverForPlaylists = await MainActor.run {
                let context = capturedCoreDataStack.viewContext
                return try! context.existingObject(with: capturedObjectID) as! CDServer
            }
            try await capturedPlaylistSyncer.syncPlaylists(for: serverForPlaylists, progressCallback: progressCallback)
            
            await MainActor.run {
                progressCallback(SyncProgress(progress: 1.0, stage: "Complete"))
            }
            
            capturedLogger.info("Full sync completed for server: \(capturedServerName)")
        }
        
        currentSyncTask[serverId] = syncTask
        
        // Wait for sync to complete and propagate errors
        do {
            try await syncTask.value
        } catch is CancellationError {
            logger.info("Sync cancelled for server: \(serverName)")
            throw SyncError.cancelled
        } catch {
            logger.error("Sync failed for server \(serverName): \(error.localizedDescription)")
            throw error
        }
    }
    
    /// Mark sync as complete
    private func markSyncComplete(serverId: UUID) async {
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
    func syncPlaylists(for server: CDServer) async throws {
        try await playlistSyncer.syncPlaylists(for: server)
    }
}

