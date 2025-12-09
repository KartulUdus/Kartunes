
import Foundation
import MediaPlayer
import UIKit
import Combine

/// Manages Now Playing info for Dynamic Island, Lock Screen, and Control Center
@MainActor
final class NowPlayingManager {
    private let logger = Log.make(.nowPlaying)
    
    private let playbackViewModel: PlaybackViewModel
    private let playbackRepository: PlaybackRepository
    private let apiClient: MediaServerAPIClient
    private var cancellables = Set<AnyCancellable>()
    private var artworkCache: [String: MPMediaItemArtwork] = [:]
    private var currentTrackId: String?
    
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
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        currentTrackId = nil
    }
    
    private func updateNowPlayingInfo(for track: Track?) {
        guard let track = track else {
            clearNowPlayingInfo()
            return
        }
        
        let trackChanged = currentTrackId != track.id
        currentTrackId = track.id
        
        var nowPlayingInfo: [String: Any] = [
            MPMediaItemPropertyTitle: track.title,
            MPMediaItemPropertyArtist: track.artistName,
            MPNowPlayingInfoPropertyPlaybackRate: playbackViewModel.isPlaying ? 1.0 : 0.0
        ]
        
        if let albumTitle = track.albumTitle {
            nowPlayingInfo[MPMediaItemPropertyAlbumTitle] = albumTitle
        }
        
        // Set elapsed playback time
        nowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = playbackViewModel.currentTime
        
        // Update duration if available
        if playbackViewModel.duration > 0 {
            nowPlayingInfo[MPMediaItemPropertyPlaybackDuration] = playbackViewModel.duration
        }
        
        // Set media type (1 = audio)
        nowPlayingInfo[MPNowPlayingInfoPropertyMediaType] = 1
        
        // Set queue info for AirPlay and system controls
        let queueCount = playbackViewModel.queue.count
        if queueCount > 0 {
            nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackQueueCount] = queueCount
            if let queueIndex = playbackViewModel.getCurrentQueueIndex() {
                nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackQueueIndex] = queueIndex
            }
        }
        
        // Set initial info without artwork
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
        
        // Load artwork asynchronously (only if track changed or we don't have it cached)
        if trackChanged || artworkCache[track.id] == nil {
            Task {
                if let artwork = await loadArtwork(for: track) {
                    await MainActor.run {
                        // Update with artwork
                        var updatedInfo = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
                        updatedInfo[MPMediaItemPropertyArtwork] = artwork
                        MPNowPlayingInfoCenter.default().nowPlayingInfo = updatedInfo
                    }
                }
            }
        }
    }
    
    private func updatePlaybackState(isPlaying: Bool) {
        var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
        info[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? 1.0 : 0.0
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = playbackViewModel.currentTime
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }
    
    private func updatePlaybackTime() {
        var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = playbackViewModel.currentTime
        if playbackViewModel.duration > 0 {
            info[MPMediaItemPropertyPlaybackDuration] = playbackViewModel.duration
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }
    
    private func updateQueueInfo() {
        var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
        let queueCount = playbackViewModel.queue.count
        if queueCount > 0 {
            info[MPNowPlayingInfoPropertyPlaybackQueueCount] = queueCount
            if let queueIndex = playbackViewModel.getCurrentQueueIndex() {
                info[MPNowPlayingInfoPropertyPlaybackQueueIndex] = queueIndex
            }
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }
    
    // MARK: - Artwork Loading
    
    private func loadArtwork(for track: Track) async -> MPMediaItemArtwork? {
        // Check cache first
        if let cached = artworkCache[track.id] {
            return cached
        }
        
        // Try to load from album ID first (use 600+ for better AirPlay display)
        if let albumId = track.albumId,
           let imageURL = apiClient.buildImageURL(forItemId: albumId, imageType: "Primary", maxWidth: 600) {
            if let artwork = await loadArtwork(from: imageURL) {
                artworkCache[track.id] = artwork
                return artwork
            }
        }
        
        // Fallback to track ID (use 600+ for better AirPlay display)
        if let imageURL = apiClient.buildImageURL(forItemId: track.id, imageType: "Primary", maxWidth: 600) {
            if let artwork = await loadArtwork(from: imageURL) {
                artworkCache[track.id] = artwork
                return artwork
            }
        }
        
        return nil
    }
    
    private func loadArtwork(from url: URL) async -> MPMediaItemArtwork? {
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let image = UIImage(data: data) else { return nil }
            
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

