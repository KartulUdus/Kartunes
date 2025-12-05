
import Foundation
import AVFoundation
@preconcurrency import CoreData

final class MediaServerPlaybackRepository: NSObject, PlaybackRepository {
    let apiClient: MediaServerAPIClient
    let coreDataStack: CoreDataStack
    let logger: AppLogger
    var player: AVQueuePlayer?
    var currentQueue: [Track] = []
    var currentIndex: Int = 0
    var resourceLoader: AuthenticatedAssetResourceLoader?
    
    // Lazy loading: only prefetch a small window of tracks ahead
    let prefetchWindow = 3 // Number of tracks to prefetch ahead
    var loadedItems: Set<Int> = [] // Track which items have been loaded
    var prefetchTask: Task<Void, Never>?
    
    // Playback reporting state
    var currentPlaySessionId: String?
    var currentMediaSourceId: String?
    var currentItemId: String?
    var progressReportingTask: Task<Void, Never>?
    var isPaused: Bool = false
    
    // Callback for handling track not found (404) errors
    var onTrackNotFound: ((String) async -> Void)? // trackId
    
    init(apiClient: MediaServerAPIClient, coreDataStack: CoreDataStack = .shared, logger: AppLogger = Log.make(.playback)) {
        self.apiClient = apiClient
        self.coreDataStack = coreDataStack
        self.logger = logger
        super.init()
        setupAudioSession()
    }
    
    private func setupAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [])
            try AVAudioSession.sharedInstance().setActive(true, options: [])
        } catch {
            logger.error("Playback: failed to setup audio session: \(error)")
        }
    }
}
