
import SwiftUI
import Combine
import AVFoundation
import Foundation
@preconcurrency import CoreData

enum RepeatMode: Equatable {
    case off
    case all
    case one
}

@MainActor
final class PlaybackViewModel: ObservableObject {
    private let logger = Log.make(.playback)
    
    @Published var currentTrack: Track?
    @Published var isPlaying = false
    @Published var currentTime: TimeInterval = 0
    @Published var duration: TimeInterval = 0
    @Published var queue: [Track] = []
    
    // Shuffle and Repeat
    @Published var isShuffleEnabled = false
    @Published var repeatMode: RepeatMode = .off
    
    private var playbackRepository: PlaybackRepository
    private var libraryRepository: LibraryRepository?
    private var timeObserver: Any?
    private var cancellables = Set<AnyCancellable>()
    @Published var albumArtCache: [String: URL] = [:] // albumId -> imageURL
    private var hasWaitedForTimebaseSync = false
    private var trackFinishedObserver: NSObjectProtocol?
    private var isSeeking = false // Flag to prevent time updates during seek
    private var seekGenerationId: Int = 0 // Track seek operations to prevent late completions
    
    // Playback Queue
    private var activeQueue: PlaybackQueue?
    
    // Shuffle state: stable shuffled order with history
    private var shuffleOrder: [Track] = [] // The stable shuffled order
    private var shuffleHistory: [Track] = [] // Stack of previously played tracks (for "previous")
    private var shuffleCurrentIndex: Int = 0 // Current position in shuffleOrder
    private var originalQueueOrder: [Track] = [] // Original order before shuffle (for reverting)
    
    // Transition lock to prevent race conditions
    private var isTransitioning = false
    private var isCreatingInstantMix = false // Guard against concurrent instantMix operations
    
    init(playbackRepository: PlaybackRepository, libraryRepository: LibraryRepository? = nil) {
        self.playbackRepository = playbackRepository
        self.libraryRepository = libraryRepository
        startTimeObserver()
        setupTrackFinishedObserver()
    }
    
    func albumArtURL(for albumId: String) -> URL? {
        // Check cache first
        if let cached = albumArtCache[albumId] {
            return cached
        }
        
        // Load album art in background
        Task {
            await loadAlbumArt(for: albumId)
        }
        
        return nil
    }
    
    private func loadAlbumArt(for albumId: String) async {
        // First, try to get from Core Data (fastest, most reliable)
        let context = CoreDataStack.shared.viewContext
        let request: NSFetchRequest<CDAlbum> = CDAlbum.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", albumId)
        request.fetchLimit = 1
        
        if let cdAlbum = try? context.fetch(request).first,
           let imageURLString = cdAlbum.imageURL,
           let imageURL = URL(string: imageURLString) {
            await MainActor.run {
                albumArtCache[albumId] = imageURL
            }
            return
        }
        
        // Fallback: try library repository
        guard let libraryRepository = libraryRepository else { return }
        
        do {
            let albums = try await libraryRepository.fetchAlbums(artistId: nil)
            if let album = albums.first(where: { $0.id == albumId }),
               let imageURL = album.thumbnailURL {
                await MainActor.run {
                    albumArtCache[albumId] = imageURL
                }
            }
        } catch {
            logger.error("Failed to load album art: \(error.localizedDescription)")
        }
    }
    
    /// Builds album art URL directly from track ID (for Emby where track has the image)
    func buildTrackImageURL(trackId: String, albumId: String?) -> URL? {
        // For Emby, try track ID first, then album ID
        // This is a fallback when album lookup fails
        // Get from Core Data track to find server, then build URL
        let context = CoreDataStack.shared.viewContext
        let request: NSFetchRequest<CDTrack> = CDTrack.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", trackId)
        request.fetchLimit = 1
        
        guard let cdTrack = try? context.fetch(request).first,
              let server = cdTrack.server else {
            logger.warning("AlbumArt: Track not found in Core Data - TrackID: \(trackId)")
            return nil
        }
        
        // Get the API client from AppCoordinator
        // Actually, simpler: build URL directly from server info
        guard let baseURLString = server.baseURL,
              let baseURL = URL(string: baseURLString),
              let accessToken = server.accessToken else {
            logger.warning("AlbumArt: Server info incomplete")
            return nil
        }
        
        // Build URL manually - use the baseURL as-is (it should already have /emby if needed)
        let serverType = server.serverType
        let imagePath = "Items/\(trackId)/Images/Primary"
        
        // Build URL components
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
        var path = components.path
        if !path.hasSuffix("/") {
            path += "/"
        }
        path += imagePath
        components.path = path
        
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "maxWidth", value: "300"),
            URLQueryItem(name: "maxHeight", value: "300")
        ]
        
        // Add quality and api_key for Emby
        if serverType == .emby {
            queryItems.append(URLQueryItem(name: "quality", value: "90"))
            queryItems.append(URLQueryItem(name: "api_key", value: accessToken))
        } else {
            // Jellyfin uses ApiKey
            queryItems.append(URLQueryItem(name: "ApiKey", value: accessToken))
        }
        
        components.queryItems = queryItems
        
        if let trackURL = components.url {
            logger.debug("AlbumArt: Built track image URL - TrackID: \(trackId), URL: \(trackURL.absoluteString)")
            return trackURL
        }
        
        // Fallback to album ID
        if let albumId = albumId {
            let albumPath = "Items/\(albumId)/Images/Primary"
            components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
            path = components.path
            if !path.hasSuffix("/") {
                path += "/"
            }
            path += albumPath
            components.path = path
            components.queryItems = queryItems
            if let albumURL = components.url {
                logger.debug("AlbumArt: Built album image URL - AlbumID: \(albumId), URL: \(albumURL.absoluteString)")
                return albumURL
            }
        }
        
        logger.warning("AlbumArt: Failed to build image URL - TrackID: \(trackId), AlbumID: \(albumId ?? "nil")")
        return nil
    }
    
    deinit {
        // Cleanup cancellables - this is safe to do from deinit
        cancellables.removeAll()
        // Remove notification observer
        if let observer = trackFinishedObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }
    
    /// Start a playback queue from a list of tracks
    func startQueue(from tracks: [Track], at index: Int, context: PlaybackContext) {
        guard !tracks.isEmpty, index >= 0, index < tracks.count else {
            logger.warning("startQueue: Invalid tracks or index")
            return
        }
        
        // Store original order
        originalQueueOrder = tracks
        
        // Reset shuffle state when starting a new queue
        if isShuffleEnabled {
            // Create stable shuffled order
            shuffleOrder = tracks.shuffled()
            shuffleHistory = []
            // Find the starting track's position in the shuffled order
            if index < tracks.count {
                let startTrack = tracks[index]
                if let shuffleIndex = shuffleOrder.firstIndex(where: { $0.id == startTrack.id }) {
                    shuffleCurrentIndex = shuffleIndex
                    // Add all tracks before current to history
                    shuffleHistory = Array(shuffleOrder[0..<shuffleIndex])
                } else {
                    shuffleCurrentIndex = 0
                }
            } else {
                shuffleCurrentIndex = 0
            }
        } else {
            shuffleOrder = []
            shuffleHistory = []
            shuffleCurrentIndex = 0
        }
        
        // Create and store the queue (no size limit - lazy loading handles performance)
        let queue = PlaybackQueue(tracks: tracks, currentIndex: index, context: context)
        activeQueue = queue
        
        // Update published properties immediately for UI
        currentTrack = queue.currentTrack
        self.queue = tracks
        hasWaitedForTimebaseSync = false
        currentTime = 0 // Reset time when starting new queue
        duration = 0 // Reset duration - will be updated when track loads
        
        logger.info("startQueue: Starting queue with \(tracks.count) tracks at index \(index), context: \(context), shuffle: \(isShuffleEnabled)")
        
        // Start playback - repository will only fetch URLs for tracks that are actually played
        Task {
            await playbackRepository.play(queue: tracks, startingAt: index, context: context)
            await updateState()
        }
    }
    
    /// Legacy method for backward compatibility - creates a single-track queue
    func play(track: Track) {
        // Create a minimal queue with just this track
        startQueue(from: [track], at: 0, context: .custom([track.id]))
    }
    
    /// Legacy method for backward compatibility
    func play(queue: [Track], startingAt index: Int) {
        // Use custom context if we don't have a better one
        startQueue(from: queue, at: index, context: .custom(queue.map { $0.id }))
    }
    
    func pause() {
        Task {
            await playbackRepository.pause()
            isPlaying = false
        }
    }
    
    func resume() {
        Task {
            await playbackRepository.resume()
            isPlaying = true
        }
    }
    
    func togglePlayPause() {
        if isPlaying {
            pause()
        } else {
            resume()
        }
    }
    
    func stop() {
        Task {
            await playbackRepository.stop()
            // Clear all playback state
            currentTrack = nil
            isPlaying = false
            currentTime = 0
            duration = 0
            queue = []
            activeQueue = nil
            hasWaitedForTimebaseSync = false
            shuffleOrder = []
            shuffleHistory = []
            shuffleCurrentIndex = 0
            originalQueueOrder = []
            isTransitioning = false
            isCreatingInstantMix = false
        }
    }
    
    func next() {
        // Prevent race conditions
        guard !isTransitioning else {
            logger.debug("next: Already transitioning, ignoring command")
            return
        }
        
        guard let queue = activeQueue else {
            // Fallback to repository if no queue
            Task {
                await playbackRepository.next()
                await updateState()
            }
            return
        }
        
        isTransitioning = true
        
        if isShuffleEnabled {
            playNextShuffledTrack()
        } else {
            // Move to next track in queue
            if queue.moveToNext() {
                currentTrack = queue.currentTrack
                self.queue = queue.tracks
                currentTime = 0
                duration = 0
                Task {
                    await playbackRepository.play(queue: queue.tracks, startingAt: queue.currentIndex, context: queue.context)
                    await updateState()
                    await MainActor.run {
                        self.isTransitioning = false
                    }
                }
            } else {
                // End of queue - handle repeat all
                if repeatMode == .all {
                    logger.debug("next: End of queue, repeat all - restarting from beginning")
                    queue.currentIndex = 0
                    currentTrack = queue.currentTrack
                    self.queue = queue.tracks
                    currentTime = 0
                    duration = 0
                    Task {
                        await playbackRepository.play(queue: queue.tracks, startingAt: 0, context: queue.context)
                        await updateState()
                        await MainActor.run {
                            self.isTransitioning = false
                        }
                    }
                } else {
                    logger.warning("next: No next track available")
                    isTransitioning = false
                }
            }
        }
    }
    
    /// Skip forward to next track (for CarPlay and iOS UI)
    func skipForwardTrack() async {
        next()
    }
    
    /// Skip back or restart current track (for CarPlay and iOS UI)
    /// If playback position < 5s, go to previous track
    /// Else, seek to start of current track
    func skipBackOrRestart() async {
        // Get the actual current time from the repository to ensure accuracy
        // The cached currentTime might be stale (updated every 1 second)
        let actualTime = await playbackRepository.getCurrentTime()
        logger.debug("skipBackOrRestart: actualTime = \(actualTime)s, cached currentTime = \(currentTime)s, duration = \(duration)s")
        
        if actualTime < 5 {
            logger.debug("skipBackOrRestart: Time < 5s, going to previous track")
            previous()
        } else {
            logger.debug("skipBackOrRestart: Time >= 5s, seeking to beginning of current track")
            seek(to: 0)
        }
    }
    
    private func playNextShuffledTrack() {
        guard let queue = activeQueue else {
            isTransitioning = false
            return
        }
        
        // Add current track to history if it exists
        if let current = queue.currentTrack {
            shuffleHistory.append(current)
        }
        
        // Move to next in shuffle order
        shuffleCurrentIndex += 1
        
        // Check if we've reached the end of shuffle order
        if shuffleCurrentIndex >= shuffleOrder.count {
            // All tracks played - handle repeat
            if repeatMode == .all {
                // Reshuffle and start over
                logger.debug("All tracks played, reshuffling")
                shuffleOrder = queue.tracks.shuffled()
                shuffleHistory = []
                shuffleCurrentIndex = 0
            } else {
                // End of queue
                logger.warning("playNextShuffledTrack: End of shuffle order")
                isTransitioning = false
                return
            }
        }
        
        // Get next track from shuffle order
        let nextTrack = shuffleOrder[shuffleCurrentIndex]
        
        // Find the index in the original queue
        if let nextIndex = queue.tracks.firstIndex(where: { $0.id == nextTrack.id }) {
            queue.currentIndex = nextIndex
            currentTrack = queue.currentTrack
            self.queue = queue.tracks
            currentTime = 0 // Reset time for new track
            duration = 0 // Reset duration - will be updated when track loads
            
            Task {
                await playbackRepository.play(queue: queue.tracks, startingAt: queue.currentIndex, context: queue.context)
                await updateState()
                await MainActor.run {
                    self.isTransitioning = false
                }
            }
        } else {
            logger.warning("playNextShuffledTrack: Track not found in original queue")
            isTransitioning = false
        }
    }
    
    func previous() {
        // Prevent race conditions
        guard !isTransitioning else {
            logger.debug("previous: Already transitioning, ignoring command")
            return
        }
        
        guard let queue = activeQueue else {
            // Fallback to repository if no queue
            Task {
                await playbackRepository.previous()
                await updateState()
            }
            return
        }
        
        isTransitioning = true
        
        if isShuffleEnabled {
            playPreviousShuffledTrack()
        } else {
            // Move to previous track in queue
            if queue.moveToPrevious() {
                currentTrack = queue.currentTrack
                self.queue = queue.tracks
                currentTime = 0
                duration = 0
                Task {
                    await playbackRepository.play(queue: queue.tracks, startingAt: queue.currentIndex, context: queue.context)
                    await updateState()
                    await MainActor.run {
                        self.isTransitioning = false
                    }
                }
            } else {
                // Beginning of queue - handle repeat all
                if repeatMode == .all {
                    logger.debug("previous: Beginning of queue, repeat all - going to end")
                    queue.currentIndex = queue.tracks.count - 1
                    currentTrack = queue.currentTrack
                    self.queue = queue.tracks
                    currentTime = 0
                    duration = 0
                    Task {
                        await playbackRepository.play(queue: queue.tracks, startingAt: queue.currentIndex, context: queue.context)
                        await updateState()
                        await MainActor.run {
                            self.isTransitioning = false
                        }
                    }
                } else {
                    logger.warning("previous: No previous track available")
                    isTransitioning = false
                }
            }
        }
    }
    
    private func playPreviousShuffledTrack() {
        guard let queue = activeQueue else {
            isTransitioning = false
            return
        }
        
        // Check if we have history to go back to
        guard !shuffleHistory.isEmpty else {
            // No history - handle repeat all
            if repeatMode == .all {
                // Go to end of shuffle order
                shuffleCurrentIndex = shuffleOrder.count - 1
                if let lastTrack = shuffleOrder.last,
                   let lastIndex = queue.tracks.firstIndex(where: { $0.id == lastTrack.id }) {
                    queue.currentIndex = lastIndex
                    currentTrack = queue.currentTrack
                    self.queue = queue.tracks
                    currentTime = 0
                    duration = 0
                    Task {
                        await playbackRepository.play(queue: queue.tracks, startingAt: queue.currentIndex, context: queue.context)
                        await updateState()
                        await MainActor.run {
                            self.isTransitioning = false
                        }
                    }
                } else {
                    isTransitioning = false
                }
            } else {
                logger.warning("playPreviousShuffledTrack: No history and repeat off")
                isTransitioning = false
            }
            return
        }
        
        // Get previous track from history
        let previousTrack = shuffleHistory.removeLast()
        
        // Update shuffle index to match
        if let historyIndex = shuffleOrder.firstIndex(where: { $0.id == previousTrack.id }) {
            shuffleCurrentIndex = historyIndex
        }
        
        // Find the index in the original queue
        if let prevIndex = queue.tracks.firstIndex(where: { $0.id == previousTrack.id }) {
            queue.currentIndex = prevIndex
            currentTrack = queue.currentTrack
            self.queue = queue.tracks
            currentTime = 0
            duration = 0
            Task {
                await playbackRepository.play(queue: queue.tracks, startingAt: queue.currentIndex, context: queue.context)
                await updateState()
                await MainActor.run {
                    self.isTransitioning = false
                }
            }
        } else {
            logger.warning("playPreviousShuffledTrack: Track not found in original queue")
            isTransitioning = false
        }
    }
    
    func skipTo(index: Int) {
        guard let queue = activeQueue else { return }
        guard index >= 0 && index < queue.tracks.count else { return }
        
        if queue.skipTo(index: index) {
            currentTrack = queue.currentTrack
            self.queue = queue.tracks
            Task {
                await playbackRepository.skipTo(index: index)
                await updateState()
            }
        }
    }
    
    /// Get all tracks in the queue (for Up Next view)
    /// Shows the entire queue so users can see all songs and which one is playing
    func getUpNextTracks() -> [Track] {
        guard let queue = activeQueue else { return [] }
        
        // If shuffle is enabled, show the shuffled order
        if isShuffleEnabled && !shuffleOrder.isEmpty {
            return shuffleOrder
        }
        
        // Otherwise return original queue order
        return queue.tracks
    }
    
    /// Get the current queue index (for Up Next view navigation)
    func getCurrentQueueIndex() -> Int? {
        return activeQueue?.currentIndex
    }
    
    /// Add a track to play next (right after the current track)
    func playNext(_ track: Track) {
        guard let queue = activeQueue else {
            // If no queue exists, start a new queue with this track
            startQueue(from: [track], at: 0, context: .custom([track.id]))
            return
        }
        
        // Insert the track right after the current index
        let insertIndex = queue.currentIndex + 1
        queue.tracks.insert(track, at: insertIndex)
        
        // Update published properties
        self.queue = queue.tracks
        
        // Update shuffle state if enabled
        if isShuffleEnabled {
            // Add to shuffle order if not already present
            if !shuffleOrder.contains(where: { $0.id == track.id }) {
                shuffleOrder.insert(track, at: shuffleCurrentIndex + 1)
            }
        }
        
        logger.debug("playNext: Added '\(track.title)' to play next at index \(insertIndex)")
    }
    
    func seek(to time: TimeInterval) {
        // Increment generation ID for this seek operation
        seekGenerationId += 1
        let currentSeekId = seekGenerationId
        
        isSeeking = true
        currentTime = time // Update immediately to prevent jitter
        
        Task {
            await playbackRepository.seek(to: time)
            
            // Wait a moment for the seek to complete, then resume time updates
            try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
            
            await MainActor.run {
                // Only update if this is still the latest seek operation
                guard currentSeekId == self.seekGenerationId else {
                    self.logger.debug("Seek operation \(currentSeekId) outdated, ignoring completion")
                    return
                }
                
                self.isSeeking = false
                // Update time once more to sync with actual player position
                Task {
                    // Final check before updating time
                    let finalSeekId = await MainActor.run { self.seekGenerationId }
                    guard currentSeekId == finalSeekId else {
                        return
                    }
                    self.currentTime = await self.playbackRepository.getCurrentTime()
                }
            }
        }
    }
    
    private func updateState() async {
        let previousTrackId = currentTrack?.id
        currentTrack = await playbackRepository.getCurrentTrack()
        queue = await playbackRepository.getQueue()
        
        // Store current track in shared state for Siri extension
        if let track = currentTrack {
            SharedPlaybackState.storeCurrentTrack(track)
            
            // Reconcile liked state from FavoritesStore when track changes
            if track.id != previousTrackId {
                let isLiked = FavoritesStore.shared.isLiked(track.id)
                if track.isLiked != isLiked {
                    // Create updated track with correct liked state
                    let updatedTrack = Track(
                        id: track.id,
                        title: track.title,
                        albumId: track.albumId,
                        albumTitle: track.albumTitle,
                        artistName: track.artistName,
                        duration: track.duration,
                        trackNumber: track.trackNumber,
                        discNumber: track.discNumber,
                        dateAdded: track.dateAdded,
                        playCount: track.playCount,
                        isLiked: isLiked,
                        streamUrl: track.streamUrl,
                        serverId: track.serverId
                    )
                    currentTrack = updatedTrack
                    
                    // Update in queue if it exists
                    if let queue = activeQueue,
                       let index = queue.tracks.firstIndex(where: { $0.id == track.id }) {
                        queue.tracks[index] = updatedTrack
                        self.queue = queue.tracks
                    }
                }
            }
        }
        
        // Log when track changes and try to get album art
        if let track = currentTrack, track.id != previousTrackId {
            let trackId = track.id
            let albumId = track.albumId ?? "nil"
            logger.debug("AlbumArt: TrackID=\(trackId), AlbumID=\(albumId), TrackTitle=\(track.title)")
            
            // Try album ID first (standard approach)
            if let albumId = track.albumId {
                if let imageURL = albumArtURL(for: albumId) {
                    logger.debug("AlbumArt: Found cached albumId URL: \(imageURL.absoluteString)")
                } else {
                    logger.debug("AlbumArt: Loading albumId URL from Core Data/Repository...")
                }
            }
            
            // Also try building directly from track ID (Emby fallback)
            if let directURL = buildTrackImageURL(trackId: trackId, albumId: track.albumId) {
                // Cache it using track ID as key for quick access
                albumArtCache[trackId] = directURL
                logger.debug("AlbumArt: Built direct track URL and cached: \(directURL.absoluteString)")
            }
        }
        
        // Always update duration when track changes or if we don't have one
        let newDuration = await playbackRepository.getDuration() ?? 0
        if newDuration > 0 {
            duration = newDuration
        } else if currentTrack?.id != previousTrackId {
            // Track changed but duration not ready yet - reset and will update when ready
            duration = 0
        }
        
        isPlaying = true
        
        // Sync activeQueue with repository state
        if let queue = activeQueue,
           let repoCurrentTrack = currentTrack,
           let queueIndex = queue.tracks.firstIndex(where: { $0.id == repoCurrentTrack.id }) {
            queue.currentIndex = queueIndex
        }
    }
    
    private func startTimeObserver() {
        // Update time every 1 second (less frequent to reduce timebase access)
        Timer.publish(every: 1.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self = self else { return }
                    // Only update time if we have a track
                    // The repository will check if the player item is ready before accessing time
                    // This prevents timestamp warnings when the item isn't ready yet
                    if self.currentTrack != nil {
                        // Wait a bit after playback starts to let timebase sync
                        // This reduces the flood of timebase errors when playback first starts
                        if !self.hasWaitedForTimebaseSync && self.isPlaying {
                            self.hasWaitedForTimebaseSync = true
                            try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second delay
                        }
                        
                        // Don't update time while seeking to prevent jitter
                        if !self.isSeeking {
                            // Only update time if we've waited for sync or if we already have a time
                            if self.hasWaitedForTimebaseSync || self.currentTime > 0 {
                                self.currentTime = await self.playbackRepository.getCurrentTime()
                            }
                        }
                        // Always try to update duration - it may change when track changes
                        if let newDuration = await self.playbackRepository.getDuration(), newDuration > 0 {
                            // Only update if it's different to avoid unnecessary updates
                            if abs(self.duration - newDuration) > 0.1 {
                                self.duration = newDuration
                            }
                        }
                    } else {
                        // Reset flag when no track
                        self.hasWaitedForTimebaseSync = false
                    }
                }
            }
            .store(in: &cancellables)
    }
    
    private func stopTimeObserver() {
        cancellables.removeAll()
    }
    
    // MARK: - Track Finished Handling
    
    private func setupTrackFinishedObserver() {
        // Register for AVPlayer end-of-track notifications
        trackFinishedObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleTrackFinished()
            }
        }
    }
    
    func handleTrackFinished() {
        guard let queue = activeQueue else {
            logger.warning("handleTrackFinished: No active queue")
            return
        }
        
        logger.debug("handleTrackFinished: Track finished. Repeat mode: \(repeatMode), Shuffle: \(isShuffleEnabled), Current index: \(queue.currentIndex)")
        
        // Handle repeat one mode
        if repeatMode == .one {
            // Restart the current track
            logger.debug("handleTrackFinished: Repeat one - restarting current track")
            currentTime = 0 // Reset time when repeating
            Task {
                await playbackRepository.play(queue: queue.tracks, startingAt: queue.currentIndex, context: queue.context)
                await updateState()
            }
            return
        }
        
        // Check if there's a next track
        let hasNext: Bool
        if isShuffleEnabled {
            hasNext = shuffleCurrentIndex < shuffleOrder.count - 1 || repeatMode == .all
        } else {
            hasNext = queue.hasNext
        }
        
        if hasNext {
            if isShuffleEnabled {
                playNextShuffledTrack()
            } else {
                // Move to next track
                _ = queue.moveToNext()
                currentTrack = queue.currentTrack
                self.queue = queue.tracks
                currentTime = 0 // Reset time for new track
                duration = 0 // Reset duration - will be updated when track loads
                
                logger.debug("handleTrackFinished: Auto-advancing to next track: \(queue.currentTrack?.title ?? "nil")")
                
                // Start playing the next track
                Task {
                    await playbackRepository.play(queue: queue.tracks, startingAt: queue.currentIndex, context: queue.context)
                    await updateState()
                }
            }
        } else {
            // End of queue - handle repeat all
            if repeatMode == .all {
                logger.debug("handleTrackFinished: Repeat all - restarting queue")
                // Reset shuffle state if enabled
                if isShuffleEnabled {
                    shuffleOrder = queue.tracks.shuffled()
                    shuffleHistory = []
                    shuffleCurrentIndex = 0
                }
                // Restart from beginning
                queue.currentIndex = 0
                currentTrack = queue.currentTrack
                Task {
                    await playbackRepository.play(queue: queue.tracks, startingAt: 0, context: queue.context)
                    await updateState()
                }
            } else {
                // End of queue, no repeat
                logger.debug("handleTrackFinished: Reached end of queue")
                isPlaying = false
            }
        }
    }
    
    // MARK: - Shuffle and Repeat Controls
    
    func toggleShuffle() {
        guard let queue = activeQueue else { return }
        
        isShuffleEnabled.toggle()
        
        if isShuffleEnabled {
            // Store original order if not already stored
            if originalQueueOrder.isEmpty {
                originalQueueOrder = queue.tracks
            }
            
            // Create stable shuffled order
            shuffleOrder = queue.tracks.shuffled()
            shuffleHistory = []
            
            // Find current track's position in shuffled order
            if let currentTrack = queue.currentTrack {
                if let shuffleIndex = shuffleOrder.firstIndex(where: { $0.id == currentTrack.id }) {
                    shuffleCurrentIndex = shuffleIndex
                    // Add all tracks before current to history
                    shuffleHistory = Array(shuffleOrder[0..<shuffleIndex])
                } else {
                    shuffleCurrentIndex = 0
                }
            } else {
                shuffleCurrentIndex = 0
            }
            
            logger.debug("Shuffle enabled with \(queue.tracks.count) tracks, current index: \(shuffleCurrentIndex)")
        } else {
            // Revert to original order
            if !originalQueueOrder.isEmpty {
                // Restore original queue order
                queue.tracks = originalQueueOrder
                // Find current track's position in original order
                if let queueCurrentTrack = queue.currentTrack,
                   let originalIndex = originalQueueOrder.firstIndex(where: { $0.id == queueCurrentTrack.id }) {
                    queue.currentIndex = originalIndex
                    self.currentTrack = queue.currentTrack
                }
                self.queue = queue.tracks
            }
            
            shuffleOrder = []
            shuffleHistory = []
            shuffleCurrentIndex = 0
            originalQueueOrder = []
            
            logger.debug("Shuffle disabled, reverted to original order")
        }
    }
    
    func toggleRepeat() {
        switch repeatMode {
        case .off:
            repeatMode = .all
        case .all:
            repeatMode = .one
        case .one:
            repeatMode = .off
        }
        logger.debug("Repeat mode changed to \(repeatMode)")
    }
    
    // MARK: - Instant Mix / Radio
    
    func startInstantMix(from itemId: String) {
        guard currentTrack != nil else {
            logger.warning("startInstantMix: No current track")
            return
        }
        
        // Determine the kind based on what we're playing
        // For now, we'll use .song as the default since we're starting from a track
        let kind: InstantMixKind = .song
        
        startInstantMix(from: itemId, kind: kind)
    }
    
    func startInstantMix(from itemId: String, kind: InstantMixKind, serverId: UUID? = nil) {
        // Prevent concurrent instantMix operations
        guard !isCreatingInstantMix else {
            logger.warning("startInstantMix: Already creating instant mix, ignoring duplicate request")
            return
        }
        
        logger.info("startInstantMix: Starting instant mix from item \(itemId), kind: \(kind)")
        isCreatingInstantMix = true
        
        Task {
            defer {
                Task { @MainActor in
                    self.isCreatingInstantMix = false
                }
            }
            
            do {
                let tracks = try await playbackRepository.generateInstantMix(from: itemId, kind: kind, serverId: serverId)
                
                guard !tracks.isEmpty else {
                    logger.warning("startInstantMix: No tracks returned from instant mix")
                    return
                }
                
                logger.info("startInstantMix: Got \(tracks.count) tracks, starting playback")
                
                // Clear current queue and start new one with instant mix tracks
                await MainActor.run {
                    // Clear shuffle state
                    shuffleOrder = []
                    shuffleHistory = []
                    shuffleCurrentIndex = 0
                    originalQueueOrder = []
                    isShuffleEnabled = false
                    
                    // Start new queue from instant mix
                    startQueue(from: tracks, at: 0, context: .instantMix(seedItemId: itemId))
                }
            } catch {
                logger.error("startInstantMix: Error: \(error.localizedDescription)")
            }
        }
    }
    
    // MARK: - Like Toggle
    
    func toggleLike() {
        guard let track = currentTrack else {
            logger.warning("toggleLike: No current track")
            return
        }
        
        // Optimistic update - update UI immediately
        let newLikedState = !track.isLiked
        FavoritesStore.shared.setLiked(track.id, newLikedState)
        
        // Create updated track with new liked state
        let updatedTrack = Track(
            id: track.id,
            title: track.title,
            albumId: track.albumId,
            albumTitle: track.albumTitle,
            artistName: track.artistName,
            duration: track.duration,
            trackNumber: track.trackNumber,
            discNumber: track.discNumber,
            dateAdded: track.dateAdded,
            playCount: track.playCount,
            isLiked: newLikedState,
            streamUrl: track.streamUrl,
            serverId: track.serverId
        )
        currentTrack = updatedTrack
        
        // Update the track in the queue if it exists
        if let queue = activeQueue,
           let index = queue.tracks.firstIndex(where: { $0.id == track.id }) {
            queue.tracks[index] = updatedTrack
            self.queue = queue.tracks
        }
        
        Task {
            do {
                let serverUpdatedTrack = try await playbackRepository.toggleLike(track: track)
                
                // Update with server response
                await MainActor.run {
                    // Reconcile with server state
                    FavoritesStore.shared.updateAfterAPICall(trackId: serverUpdatedTrack.id, isLiked: serverUpdatedTrack.isLiked, serverId: serverUpdatedTrack.serverId)
                    
                    // Update current track with server response
                    if currentTrack?.id == serverUpdatedTrack.id {
                        currentTrack = serverUpdatedTrack
                        
                        // Update the track in the queue if it exists
                        if let queue = activeQueue,
                           let index = queue.tracks.firstIndex(where: { $0.id == serverUpdatedTrack.id }) {
                            queue.tracks[index] = serverUpdatedTrack
                            self.queue = queue.tracks
                        }
                    }
                }
                
                logger.info("toggleLike: Successfully toggled like status")
                
                // Update liked playlist (don't fail the like toggle if this fails)
                await updateLikedPlaylist(track: serverUpdatedTrack, wasLiked: serverUpdatedTrack.isLiked)
            } catch {
                // Revert on error
                logger.error("toggleLike: Error: \(error.localizedDescription)")
                await MainActor.run {
                    // Revert optimistic update
                    FavoritesStore.shared.setLiked(track.id, !newLikedState)
                    if let originalTrack = activeQueue?.tracks.first(where: { $0.id == track.id }) {
                        currentTrack = originalTrack
                        if let queue = activeQueue,
                           let index = queue.tracks.firstIndex(where: { $0.id == track.id }) {
                            queue.tracks[index] = originalTrack
                            self.queue = queue.tracks
                        }
                    }
                }
            }
        }
    }
    
    /// Updates the "Kartunes Liked {userName}" playlist based on like status
    private func updateLikedPlaylist(track: Track, wasLiked: Bool) async {
        guard let libraryRepository = libraryRepository else {
            logger.warning("updateLikedPlaylist: No library repository")
            return
        }
        
        let manager = LikedPlaylistManager(
            libraryRepository: libraryRepository,
            coreDataStack: CoreDataStack.shared,
            serverId: track.serverId
        )
        
        do {
            if wasLiked {
                // Add track to liked playlist at index 0
                try await manager.addTrackToLikedPlaylist(trackId: track.id)
            } else {
                // Remove track from liked playlist
                try await manager.removeTrackFromLikedPlaylist(trackId: track.id)
            }
        } catch {
            // Log error but don't fail the like toggle
            logger.warning("updateLikedPlaylist: Failed to update liked playlist: \(error.localizedDescription)")
        }
    }
    
    // Update repositories without losing state
    func updateRepositories(playbackRepository: PlaybackRepository, libraryRepository: LibraryRepository?) {
        self.playbackRepository = playbackRepository
        self.libraryRepository = libraryRepository
    }
}

