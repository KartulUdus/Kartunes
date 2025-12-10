
import Foundation
import MediaPlayer
import UIKit
import Combine

/// Manages Now Playing info for Dynamic Island, Lock Screen, and Control Center
/// Uses centralized NowPlayingInfoManager actor for all MPNowPlayingInfoCenter updates
@MainActor
final class NowPlayingManager {
    private let logger = Log.make(.nowPlaying)
    
    private let playbackViewModel: PlaybackViewModel
    private let playbackRepository: PlaybackRepository
    private let apiClient: MediaServerAPIClient
    private var cancellables = Set<AnyCancellable>()
    private let nowPlayingInfoManager = NowPlayingInfoManager.shared
    
    init(
        playbackViewModel: PlaybackViewModel,
        playbackRepository: PlaybackRepository,
        apiClient: MediaServerAPIClient
    ) {
        self.playbackViewModel = playbackViewModel
        self.playbackRepository = playbackRepository
        self.apiClient = apiClient
        
        setupRemoteCommands()
        setupObservers()
    }
    
    // MARK: - Remote Commands
    
    private func setupRemoteCommands() {
        let commandCenter = MPRemoteCommandCenter.shared()
        
        // Play
        commandCenter.playCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.playbackRepository.resume()
                self?.playbackViewModel.isPlaying = true
            }
            return .success
        }
        
        // Pause
        commandCenter.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.playbackRepository.pause()
                self?.playbackViewModel.isPlaying = false
            }
            return .success
        }
        
        // Toggle Play/Pause
        commandCenter.togglePlayPauseCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in
                if self?.playbackViewModel.isPlaying == true {
                    await self?.playbackRepository.pause()
                    self?.playbackViewModel.isPlaying = false
                } else {
                    await self?.playbackRepository.resume()
                    self?.playbackViewModel.isPlaying = true
                }
            }
            return .success
        }
        
        // Next Track
        commandCenter.nextTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.playbackViewModel.next()
            }
            return .success
        }
        
        // Previous Track
        commandCenter.previousTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.playbackViewModel.skipBackOrRestart()
            }
            return .success
        }
        
        // Change Playback Position (for scrubbing/seeking)
        commandCenter.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else {
                return .commandFailed
            }
            Task { @MainActor [weak self] in
                self?.playbackViewModel.seek(to: event.positionTime)
            }
            return .success
        }
        
        // Enable all commands
        commandCenter.playCommand.isEnabled = true
        commandCenter.pauseCommand.isEnabled = true
        commandCenter.togglePlayPauseCommand.isEnabled = true
        commandCenter.nextTrackCommand.isEnabled = true
        commandCenter.previousTrackCommand.isEnabled = true
        commandCenter.changePlaybackPositionCommand.isEnabled = true
    }
    
    // MARK: - Observers
    
    private func setupObservers() {
        // Observe current track changes
        playbackViewModel.$currentTrack
            .sink { [weak self] track in
                if track == nil {
                    // Track is nil - clear Now Playing info
                    self?.clearNowPlayingInfo()
                } else {
                    // Track exists - update Now Playing info
                    self?.updateNowPlayingInfo(for: track)
                }
            }
            .store(in: &cancellables)
        
        // Observe playback state
        playbackViewModel.$isPlaying
            .sink { [weak self] isPlaying in
                // Only update playback state if we have a track
                if self?.playbackViewModel.currentTrack != nil {
                    self?.updatePlaybackState(isPlaying: isPlaying)
                }
            }
            .store(in: &cancellables)
        
        // Observe time updates (throttled to avoid spamming)
        playbackViewModel.$currentTime
            .throttle(for: .seconds(1), scheduler: DispatchQueue.main, latest: true)
            .sink { [weak self] _ in
                // Only update time if we have a track
                if self?.playbackViewModel.currentTrack != nil {
                    self?.updatePlaybackTime()
                }
            }
            .store(in: &cancellables)
        
        // Observe duration changes
        playbackViewModel.$duration
            .sink { [weak self] _ in
                // Only update if we have a track
                if self?.playbackViewModel.currentTrack != nil {
                    self?.updatePlaybackTime()
                }
            }
            .store(in: &cancellables)
        
        // Observe queue changes to update queue count and index
        playbackViewModel.$queue
            .sink { [weak self] _ in
                // Only update if we have a track
                if self?.playbackViewModel.currentTrack != nil {
                    self?.updateQueueInfo()
                }
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Now Playing Info
    
    func clearNowPlayingInfo() {
        Task {
            await nowPlayingInfoManager.clear()
        }
    }
    
    private func updateNowPlayingInfo(for track: Track?) {
        guard let track = track else {
            clearNowPlayingInfo()
            return
        }
        
        let queueCount = playbackViewModel.queue.count
        let queueIndex = playbackViewModel.getCurrentQueueIndex()
        
        // Update track info through centralized manager
        Task {
            let _ = await nowPlayingInfoManager.updateTrack(
                track: track,
                isPlaying: playbackViewModel.isPlaying,
                currentTime: playbackViewModel.currentTime,
                duration: playbackViewModel.duration,
                queueCount: queueCount,
                queueIndex: queueIndex
            )
            
            // Check if we need to load artwork
            let cachedArtwork = await nowPlayingInfoManager.getCachedArtwork(trackId: track.id)
            if cachedArtwork == nil {
                // Load artwork asynchronously
                let requestId = await nowPlayingInfoManager.getArtworkRequestId()
                let loadingTrackId = track.id
                
                if let artwork = await loadArtwork(for: track, requestId: requestId, trackId: loadingTrackId) {
                    // Update artwork through centralized manager
                    let applied = await nowPlayingInfoManager.updateArtwork(
                        artwork: artwork,
                        trackId: loadingTrackId,
                        artworkRequestId: requestId
                    )
                    if !applied {
                        logger.debug("Artwork update rejected - track or request changed")
                    }
                }
            }
        }
    }
    
    private func updatePlaybackState(isPlaying: Bool) {
        let trackId = playbackViewModel.currentTrack?.id
        let currentTime = playbackViewModel.currentTime
        
        Task {
            let applied = await nowPlayingInfoManager.updatePlaybackState(
                isPlaying: isPlaying,
                currentTime: currentTime,
                trackId: trackId
            )
            if !applied {
                // Track changed, trigger full update
                if let track = playbackViewModel.currentTrack {
                    updateNowPlayingInfo(for: track)
                }
            }
        }
    }
    
    private func updatePlaybackTime() {
        let trackId = playbackViewModel.currentTrack?.id
        let currentTime = playbackViewModel.currentTime
        let duration = playbackViewModel.duration
        
        Task {
            let applied = await nowPlayingInfoManager.updatePlaybackTime(
                currentTime: currentTime,
                duration: duration,
                trackId: trackId
            )
            if !applied {
                // Track changed, ignore time update
            }
        }
    }
    
    private func updateQueueInfo() {
        let trackId = playbackViewModel.currentTrack?.id
        let queueCount = playbackViewModel.queue.count
        let queueIndex = playbackViewModel.getCurrentQueueIndex()
        
        Task {
            let applied = await nowPlayingInfoManager.updateQueueInfo(
                queueCount: queueCount,
                queueIndex: queueIndex,
                trackId: trackId
            )
            if !applied {
                // Track changed, ignore queue update
            }
        }
    }
    
    // MARK: - Artwork Loading
    
    private func loadArtwork(for track: Track, requestId: Int, trackId: String) async -> MPMediaItemArtwork? {
        // Check if request is still valid via centralized manager
        let currentTrackId = await nowPlayingInfoManager.getCurrentTrackId()
        guard currentTrackId == trackId else { return nil }
        
        // Check cache first
        if let cached = await nowPlayingInfoManager.getCachedArtwork(trackId: track.id) {
            return cached
        }
        
        // Try to load from album ID first (use 600+ for better AirPlay display)
        if let albumId = track.albumId,
           let imageURL = apiClient.buildImageURL(forItemId: albumId, imageType: "Primary", maxWidth: 600) {
            if let artwork = await loadArtwork(from: imageURL, requestId: requestId, trackId: trackId) {
                return artwork
            }
        }
        
        // Fallback to track ID (use 600+ for better AirPlay display)
        if let imageURL = apiClient.buildImageURL(forItemId: track.id, imageType: "Primary", maxWidth: 600) {
            if let artwork = await loadArtwork(from: imageURL, requestId: requestId, trackId: trackId) {
                return artwork
            }
        }
        
        return nil
    }
    
    private func loadArtwork(from url: URL, requestId: Int, trackId: String) async -> MPMediaItemArtwork? {
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            
            // Check if request is still valid before processing
            let currentTrackId = await nowPlayingInfoManager.getCurrentTrackId()
            guard currentTrackId == trackId else { return nil }
            
            guard let image = UIImage(data: data) else { return nil }
            
            // Final check before returning
            let finalTrackId = await nowPlayingInfoManager.getCurrentTrackId()
            guard finalTrackId == trackId else { return nil }
            
            return MPMediaItemArtwork(boundsSize: image.size) { _ in
                return image
            }
        } catch {
            logger.error("Failed to load artwork from \(url): \(error.localizedDescription)")
            return nil
        }
    }
    
    // MARK: - Cleanup
    
    func stop() {
        cancellables.removeAll()
        let commandCenter = MPRemoteCommandCenter.shared()
        commandCenter.playCommand.removeTarget(nil)
        commandCenter.pauseCommand.removeTarget(nil)
        commandCenter.togglePlayPauseCommand.removeTarget(nil)
        commandCenter.nextTrackCommand.removeTarget(nil)
        commandCenter.previousTrackCommand.removeTarget(nil)
        commandCenter.changePlaybackPositionCommand.removeTarget(nil)
    }
}

