
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
    
    // Playback Queue
    private var activeQueue: PlaybackQueue?
    
    // Shuffle state: tracks which songs have been played
    private var shufflePlayedTracks: Set<String> = []
    private var shuffleRemainingTracks: [Track] = []
    
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
        
        // Reset shuffle state when starting a new queue
        if isShuffleEnabled {
            shufflePlayedTracks.removeAll()
            shuffleRemainingTracks = tracks.shuffled()
            // Mark the starting track as played
            shufflePlayedTracks.insert(tracks[index].id)
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
            await playbackRepository.play(queue: tracks, startingAt: index)
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
            shufflePlayedTracks.removeAll()
            shuffleRemainingTracks.removeAll()
        }
    }
    
    func next() {
        guard let queue = activeQueue else {
            // Fallback to repository if no queue
            Task {
                await playbackRepository.next()
                await updateState()
            }
            return
        }
        
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
                    await playbackRepository.play(queue: queue.tracks, startingAt: queue.currentIndex)
                    await updateState()
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
                        await playbackRepository.play(queue: queue.tracks, startingAt: 0)
                        await updateState()
                    }
                } else {
                    logger.warning("next: No next track available")
                }
            }
        }
    }
    
    private func playNextShuffledTrack() {
        guard let queue = activeQueue else { return }
        
        // Get tracks that haven't been played yet
        let unplayedTracks = shuffleRemainingTracks.filter { !shufflePlayedTracks.contains($0.id) }
        
        if unplayedTracks.isEmpty {
            // All tracks have been played, reset and shuffle again
            logger.debug("All tracks played, reshuffling")
            shufflePlayedTracks.removeAll()
            shuffleRemainingTracks = queue.tracks.shuffled()
            playNextShuffledTrack()
            return
        }
        
        // Pick a random unplayed track
        let nextTrack = unplayedTracks.randomElement()!
        shufflePlayedTracks.insert(nextTrack.id)
        
        // Find the index in the original queue
        if let nextIndex = queue.tracks.firstIndex(where: { $0.id == nextTrack.id }) {
            queue.currentIndex = nextIndex
            currentTrack = queue.currentTrack
            self.queue = queue.tracks
            currentTime = 0 // Reset time for new track
            duration = 0 // Reset duration - will be updated when track loads
            
            Task {
                await playbackRepository.play(queue: queue.tracks, startingAt: queue.currentIndex)
                await updateState()
            }
        }
    }
    
    func previous() {
        guard let queue = activeQueue else {
            // Fallback to repository if no queue
            Task {
                await playbackRepository.previous()
                await updateState()
            }
            return
        }
        
        // Move to previous track in queue
        if queue.moveToPrevious() {
            currentTrack = queue.currentTrack
            self.queue = queue.tracks
            currentTime = 0
            duration = 0
            Task {
                await playbackRepository.play(queue: queue.tracks, startingAt: queue.currentIndex)
                await updateState()
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
                    await playbackRepository.play(queue: queue.tracks, startingAt: queue.currentIndex)
                    await updateState()
                }
            } else {
                logger.warning("previous: No previous track available")
            }
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
        
        // Always return all tracks in the queue
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
            // Remove from shuffle remaining if it's there
            shuffleRemainingTracks.removeAll { $0.id == track.id }
        }
        
        logger.debug("playNext: Added '\(track.title)' to play next at index \(insertIndex)")
    }
    
    func seek(to time: TimeInterval) {
        isSeeking = true
        currentTime = time // Update immediately to prevent jitter
        Task {
            await playbackRepository.seek(to: time)
            // Wait a moment for the seek to complete, then resume time updates
            try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
            await MainActor.run {
                self.isSeeking = false
                // Update time once more to sync with actual player position
                Task {
                    self.currentTime = await self.playbackRepository.getCurrentTime()
                }
            }
        }
    }
    
    private func updateState() async {
        let previousTrackId = currentTrack?.id
        currentTrack = await playbackRepository.getCurrentTrack()
        queue = await playbackRepository.getQueue()
        
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
                await playbackRepository.play(queue: queue.tracks, startingAt: queue.currentIndex)
                await updateState()
            }
            return
        }
        
        // Check if there's a next track
        let hasNext: Bool
        if isShuffleEnabled {
            // Check if there are unplayed tracks
            let unplayedTracks = shuffleRemainingTracks.filter { !shufflePlayedTracks.contains($0.id) }
            hasNext = !unplayedTracks.isEmpty || shufflePlayedTracks.count < queue.tracks.count
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
                    await playbackRepository.play(queue: queue.tracks, startingAt: queue.currentIndex)
                    await updateState()
                }
            }
        } else {
            // End of queue - handle repeat all
            if repeatMode == .all {
                logger.debug("handleTrackFinished: Repeat all - restarting queue")
                // Reset shuffle state if enabled
                if isShuffleEnabled {
                    shufflePlayedTracks.removeAll()
                    shuffleRemainingTracks = queue.tracks.shuffled()
                }
                // Restart from beginning
                queue.currentIndex = 0
                currentTrack = queue.currentTrack
                Task {
                    await playbackRepository.play(queue: queue.tracks, startingAt: 0)
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
        isShuffleEnabled.toggle()
        
        if isShuffleEnabled {
            // Initialize shuffle state
            guard let queue = activeQueue else { return }
            shuffleRemainingTracks = queue.tracks.shuffled()
            shufflePlayedTracks.removeAll()
            // Mark current track as played
            if let currentTrack = queue.currentTrack {
                shufflePlayedTracks.insert(currentTrack.id)
            }
            logger.debug("Shuffle enabled with \(queue.tracks.count) tracks")
        } else {
            shufflePlayedTracks.removeAll()
            shuffleRemainingTracks.removeAll()
            logger.debug("Shuffle disabled")
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
        logger.info("startInstantMix: Starting instant mix from item \(itemId), kind: \(kind)")
        
        Task {
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
                    shufflePlayedTracks.removeAll()
                    shuffleRemainingTracks.removeAll()
                    isShuffleEnabled = false
                    
                    // Start new queue from instant mix
                    startQueue(from: tracks, at: 0, context: .custom(tracks.map { $0.id }))
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
        
        Task {
            do {
                let updatedTrack = try await playbackRepository.toggleLike(track: track)
                
                // Update the current track
                await MainActor.run {
                    currentTrack = updatedTrack
                    
                    // Update the track in the queue if it exists
                    if let queue = activeQueue,
                       let index = queue.tracks.firstIndex(where: { $0.id == track.id }) {
                        queue.tracks[index] = updatedTrack
                        self.queue = queue.tracks
                    }
                }
                
                logger.info("toggleLike: Successfully toggled like status")
                
                // Update liked playlist (don't fail the like toggle if this fails)
                await updateLikedPlaylist(track: updatedTrack, wasLiked: updatedTrack.isLiked)
            } catch {
                logger.error("toggleLike: Error: \(error.localizedDescription)")
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

