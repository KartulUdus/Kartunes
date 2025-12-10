
import Foundation
import SwiftUI
import Combine
import CoreData

// MARK: - Toast Message

struct ToastMessage: Identifiable {
    let id = UUID()
    let message: String
    let actionText: String?
    let action: (() -> Void)?
    
    init(message: String, actionText: String? = nil, action: (() -> Void)? = nil) {
        self.message = message
        self.actionText = actionText
        self.action = action
    }
}

@MainActor
final class AppCoordinator: ObservableObject {
    private let logger = Log.make(.appCoordinator)
    
    // Repositories (will be recreated when server changes)
    private(set) var authRepository: AuthRepository
    private(set) var libraryRepository: LibraryRepository
    private(set) var playbackRepository: PlaybackRepository
    let preferencesRepository: PreferencesRepository
    
    // API Client (for downloads, etc.)
    private(set) var apiClient: MediaServerAPIClient?
    
    // Sync Manager (will be recreated when server changes)
    private(set) var syncManager: MediaServerSyncManager?
    
    // Use Cases (will be recreated when server changes)
    private(set) var fetchLibraryOverviewUseCase: FetchLibraryOverviewUseCase
    private(set) var generateInstantMixUseCase: GenerateInstantMixUseCase
    private(set) var toggleLikeTrackUseCase: ToggleLikeTrackUseCase
    private(set) var shuffleByArtistUseCase: ShuffleByArtistUseCase
    private(set) var searchLibraryUseCase: SearchLibraryUseCase
    
    // ViewModels
    @Published var playbackViewModel: PlaybackViewModel
    
    // Now Playing Manager (for Dynamic Island, Lock Screen, Control Center)
    private(set) var nowPlayingManager: NowPlayingManager?
    
    // Watch Connectivity Service (for Apple Watch companion app)
    private(set) var watchConnectivityService: WatchConnectivityService?
    
    // CarPlay
    private(set) var carPlaySceneDelegate: CarPlaySceneDelegate?
    
    func setCarPlaySceneDelegate(_ delegate: CarPlaySceneDelegate?) {
        carPlaySceneDelegate = delegate
    }
    
    // Siri
    private(set) var siriPlaybackCoordinator: SiriPlaybackCoordinator?
    private let siriRequestManager = SiriPlaybackRequestManager()
    
    // Static reference for CarPlay delegate access
    static weak var shared: AppCoordinator?
    
    // Sync State
    @Published var isSyncing = false
    @Published var syncProgress: Double = 0.0
    @Published var syncStage: String = ""
    
    // Toast Messages
    @Published var toastMessage: ToastMessage?
    
    // State
    @Published var activeServer: Server? {
        didSet {
            updateRepositories()
        }
    }
    
    init() {
        // Create placeholder repositories - will be updated when server is loaded
        let placeholderClient = MediaServerAPIClientFactory.createClient(
            serverType: .jellyfin,
            baseURL: URL(string: "https://example.com")!
        )
        let placeholderServerId = UUID()
        
        self.authRepository = MediaServerAuthRepository(apiClient: placeholderClient)
        self.libraryRepository = MediaServerLibraryRepository(apiClient: placeholderClient, serverId: placeholderServerId)
        let placeholderPlaybackRepo = MediaServerPlaybackRepository(apiClient: placeholderClient, coreDataStack: .shared)
        self.playbackRepository = placeholderPlaybackRepo
        self.preferencesRepository = MediaServerPreferencesRepository()
        
        self.fetchLibraryOverviewUseCase = FetchLibraryOverviewUseCase(libraryRepository: libraryRepository)
        
        // Create PlaybackViewModel
        self.playbackViewModel = PlaybackViewModel(playbackRepository: playbackRepository, libraryRepository: libraryRepository)
        self.generateInstantMixUseCase = GenerateInstantMixUseCase(playbackRepository: playbackRepository)
        self.toggleLikeTrackUseCase = ToggleLikeTrackUseCase(playbackRepository: playbackRepository)
        self.shuffleByArtistUseCase = ShuffleByArtistUseCase(
            libraryRepository: libraryRepository,
            playbackRepository: playbackRepository
        )
        self.searchLibraryUseCase = SearchLibraryUseCase(libraryRepository: libraryRepository)
        
        // Set callback for track not found (404) errors (after all properties are initialized)
        placeholderPlaybackRepo.onTrackNotFound = { [weak self] trackId in
            await MainActor.run {
                self?.showTrackNotFoundToast()
            }
        }
        
        // Create NowPlayingManager (will be updated when server is loaded)
        self.nowPlayingManager = NowPlayingManager(
            playbackViewModel: playbackViewModel,
            playbackRepository: playbackRepository,
            apiClient: placeholderClient
        )
        
        // Create WatchConnectivityService (will be updated when server is loaded)
        self.watchConnectivityService = WatchConnectivityService(
            playbackViewModel: playbackViewModel,
            playbackRepository: playbackRepository,
            apiClient: placeholderClient,
            coreDataStack: .shared
        )
        
        // Set shared reference for CarPlay delegate access
        AppCoordinator.shared = self
        
        // Create Siri playback coordinator (will be updated when server is loaded)
        self.siriPlaybackCoordinator = SiriPlaybackCoordinator(
            playbackViewModel: playbackViewModel,
            libraryRepository: libraryRepository
        )
    }
    
    func loadActiveServer() async {
        // DIAGNOSTIC: Test OSLog when app actually does something
        logger.error("DIAGNOSTIC - AppCoordinator.loadActiveServer called")
        NSLog("DIAGNOSTIC - AppCoordinator.loadActiveServer called (NSLog)")
        
        do {
            let server = try await authRepository.getActiveServer()
            logger.info("Loaded active server - \(server.name) at \(server.baseURL)")
            logger.debug("  - UserId: \(server.userId)")
            logger.debug("  - AccessToken: \(server.accessToken.prefix(10))...")
            // Use stored URL directly - redirects are already resolved during authentication
            activeServer = server
            
            // Check if we need to perform initial sync
            await ensureInitialData(for: server)
        } catch {
            logger.error("Failed to load active server: \(error.localizedDescription)")
            activeServer = nil
        }
    }
    
    /// Ensures initial data is synced for the server
    private func ensureInitialData(for server: Server) async {
        let context = CoreDataStack.shared.newBackgroundContext()
        let cdServer: CDServer? = try? await context.perform {
            let request: NSFetchRequest<CDServer> = CDServer.fetchRequest()
            request.predicate = NSPredicate(format: "id == %@", server.id as CVarArg)
            request.fetchLimit = 1
            return try context.fetch(request).first
        }
        
        guard let cdServer = cdServer else {
            logger.warning("Could not find server in Core Data")
            return
        }
        
        // Check if we need to trigger a sync:
        // 1. No previous sync (lastFullSync == nil)
        // 2. Last sync was more than 7 days ago
        let shouldSync: Bool
        if let lastSync = cdServer.lastFullSync {
            let daysSinceSync = Calendar.current.dateComponents([.day], from: lastSync, to: Date()).day ?? 0
            shouldSync = daysSinceSync >= 7
            if shouldSync {
                logger.info("Last sync was \(daysSinceSync) days ago (>= 7 days), triggering automatic library scan")
            } else {
                logger.debug("Server has existing sync data (last sync: \(lastSync), \(daysSinceSync) days ago)")
            }
        } else {
            shouldSync = true
            logger.info("No previous sync found, triggering initial full sync")
        }
        
        if shouldSync {
            guard let syncManager = syncManager else {
                logger.warning("Sync manager not available")
                return
            }
            
            await MainActor.run {
                isSyncing = true
                syncProgress = 0.0
                syncStage = "Starting..."
            }
            
            do {
                try await syncManager.performFullSync(for: cdServer) { progress in
                    self.syncProgress = progress.progress
                    self.syncStage = progress.stage
                }
                await MainActor.run {
                    isSyncing = false
                    syncProgress = 1.0
                    syncStage = "Complete"
                }
                logger.info("Library scan completed")
            } catch {
                await MainActor.run {
                    isSyncing = false
                    syncProgress = 0.0
                    syncStage = ""
                }
                logger.error("Library scan failed: \(error.localizedDescription)")
            }
        }
    }
    
    private func updateRepositories() {
        guard let server = activeServer else {
            logger.debug("No active server, skipping repository update")
            return
        }
        
        logger.info("Updating repositories for server: \(server.name)")
        logger.debug("  - BaseURL: \(server.baseURL)")
        logger.debug("  - UserId: \(server.userId)")
        logger.debug("  - Has access token: \(!server.accessToken.isEmpty)")
        
        // Create API client with server credentials using factory
        let apiClient = MediaServerAPIClientFactory.createClient(for: server)
        self.apiClient = apiClient
        
        // Recreate repositories with new API client and server ID
        self.authRepository = MediaServerAuthRepository(apiClient: apiClient)
        self.libraryRepository = MediaServerLibraryRepository(apiClient: apiClient, serverId: server.id)
        let playbackRepo = MediaServerPlaybackRepository(apiClient: apiClient, coreDataStack: .shared)
        
        // Set callback for track not found (404) errors
        playbackRepo.onTrackNotFound = { [weak self] trackId in
            await MainActor.run {
                self?.showTrackNotFoundToast()
            }
        }
        
        self.playbackRepository = playbackRepo
        
        // Recreate sync manager with new API client
        self.syncManager = MediaServerSyncManager.create(apiClient: apiClient)
        
        // Reset sync state when server changes
        self.isSyncing = false
        self.syncProgress = 0.0
        self.syncStage = ""
        
        // Recreate use cases with new repositories
        self.fetchLibraryOverviewUseCase = FetchLibraryOverviewUseCase(libraryRepository: libraryRepository)
        self.generateInstantMixUseCase = GenerateInstantMixUseCase(playbackRepository: playbackRepository)
        self.toggleLikeTrackUseCase = ToggleLikeTrackUseCase(playbackRepository: playbackRepository)
        self.shuffleByArtistUseCase = ShuffleByArtistUseCase(
            libraryRepository: libraryRepository,
            playbackRepository: playbackRepository
        )
        self.searchLibraryUseCase = SearchLibraryUseCase(libraryRepository: libraryRepository)
        
        // Set callback for track not found (404) errors
        if let playbackRepo = playbackRepository as? MediaServerPlaybackRepository {
            playbackRepo.onTrackNotFound = { [weak self] trackId in
                await MainActor.run {
                    self?.showTrackNotFoundToast()
                }
            }
        }
        
        // Update PlaybackViewModel with new repository without losing state
        self.playbackViewModel.updateRepositories(playbackRepository: playbackRepository, libraryRepository: libraryRepository)
        
        // Update Siri playback coordinator with new repositories
        self.siriPlaybackCoordinator = SiriPlaybackCoordinator(
            playbackViewModel: playbackViewModel,
            libraryRepository: libraryRepository
        )
        
        // Check for pending Siri requests
        checkForPendingSiriRequest()
        checkForPendingLikeRequest()
        
        // Update NowPlayingManager with new repositories
        self.nowPlayingManager?.stop()
        self.nowPlayingManager = NowPlayingManager(
            playbackViewModel: playbackViewModel,
            playbackRepository: playbackRepository,
            apiClient: apiClient
        )
        
        // Update WatchConnectivityService with new repositories
        self.watchConnectivityService = WatchConnectivityService(
            playbackViewModel: playbackViewModel,
            playbackRepository: playbackRepository,
            apiClient: apiClient,
            coreDataStack: .shared
        )
        
        // Update CarPlay scene delegate if it exists
        if let carPlayDelegate = carPlaySceneDelegate {
            carPlayDelegate.updateRepositories(
                playbackViewModel: playbackViewModel,
                libraryRepository: libraryRepository,
                playbackRepository: playbackRepository
            )
        }
        
        // Report capabilities when server is loaded/updated
        Task {
            try? await apiClient.reportCapabilities()
        }
    }
    
    func createCarPlaySceneDelegate() -> CarPlaySceneDelegate {
        let delegate = CarPlaySceneDelegate(
            playbackViewModel: playbackViewModel,
            libraryRepository: libraryRepository,
            playbackRepository: playbackRepository
        )
        carPlaySceneDelegate = delegate
        return delegate
    }
    
    // MARK: - Toast Messages
    
    func showTrackNotFoundToast() {
        toastMessage = ToastMessage(
            message: "Track not found. Might need to run library scan.",
            actionText: "Run library scan"
        ) { [weak self] in
            // Navigation to settings will be handled by the view
            self?.toastMessage = nil
        }
    }
    
    // MARK: - Siri Integration
    
    /// Check for and handle pending Siri playback requests
    func checkForPendingSiriRequest() {
        guard let request = siriRequestManager.consumeRequest() else {
            return
        }
        
        logger.info("Found pending Siri playback request: \(request)")
        
        guard let coordinator = siriPlaybackCoordinator else {
            logger.warning("Siri playback coordinator not available")
            return
        }
        
        coordinator.handle(request)
    }
    
    /// Check for and handle pending Siri like/unlike requests
    func checkForPendingLikeRequest() {
        guard let request = SharedPlaybackState.consumePendingLikeRequest() else {
            return
        }
        
        logger.info("Found pending Siri like request: trackId=\(request.trackId), isLike=\(request.isLike)")
        
        Task { @MainActor in
            // Find the track in the current queue or fetch it
            let track: Track?
            
            // First, try to find it in the current queue
            if let queueTrack = playbackViewModel.queue.first(where: { $0.id == request.trackId }) {
                track = queueTrack
            } else if let currentTrack = playbackViewModel.currentTrack, currentTrack.id == request.trackId {
                track = currentTrack
            } else {
                // Track not in queue, try to find it via MediaCatalogService
                let catalogService = MediaCatalogService()
                track = await catalogService.findTrack(byId: request.trackId)
            }
            
            guard let trackToLike = track else {
                logger.warning("Siri like: Track \(request.trackId) not found")
                return
            }
            
            // Check if the track is already in the desired state
            if trackToLike.isLiked == request.isLike {
                logger.debug("Siri like: Track already in desired state")
                return
            }
            
            // Toggle like status (this will handle API call, Core Data update, and playlist update)
            do {
                let updatedTrack = try await playbackRepository.toggleLike(track: trackToLike)
                
                // Update the current track if it's the one we just liked
                if playbackViewModel.currentTrack?.id == updatedTrack.id {
                    playbackViewModel.currentTrack = updatedTrack
                }
                
                // Update the track in the queue if it exists
                playbackViewModel.queue = playbackViewModel.queue.map { track in
                    track.id == trackToLike.id ? updatedTrack : track
                }
                
                logger.info("Siri like: Successfully \(request.isLike ? "liked" : "unliked") track \(trackToLike.title)")
            } catch {
                logger.error("Siri like: Failed to toggle like status: \(error.localizedDescription)")
            }
        }
    }
}

