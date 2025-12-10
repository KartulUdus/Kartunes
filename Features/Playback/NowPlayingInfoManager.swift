
import Foundation
import MediaPlayer
import UIKit

/// Centralized actor for managing MPNowPlayingInfoCenter updates
/// Prevents race conditions and ensures single source of truth for Now Playing info
actor NowPlayingInfoManager {
    nonisolated static let shared = NowPlayingInfoManager()
    
    private var currentTrackId: String?
    private var updateGenerationId: Int = 0
    private var artworkCache: [String: MPMediaItemArtwork] = [:]
    private var artworkRequestId: Int = 0
    nonisolated private let logger: AppLogger
    
    nonisolated private init() {
        self.logger = Log.make(.nowPlaying)
    }
    
    // MARK: - Track Info Updates
    
    /// Update Now Playing info for a track
    /// - Parameters:
    ///   - track: The track to display (nil to clear)
    ///   - isPlaying: Current playback state
    ///   - currentTime: Current playback time
    ///   - duration: Track duration
    ///   - queueCount: Number of tracks in queue
    ///   - queueIndex: Current index in queue
    /// - Returns: Update generation ID for this update
    func updateTrack(
        track: Track?,
        isPlaying: Bool,
        currentTime: TimeInterval,
        duration: TimeInterval,
        queueCount: Int,
        queueIndex: Int?
    ) async -> Int {
        updateGenerationId += 1
        let updateId = updateGenerationId
        
        // Clear if no track
        guard let track = track else {
            currentTrackId = nil
            await MainActor.run {
                MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            }
            return updateId
        }
        
        // Check if track changed
        let trackChanged = currentTrackId != track.id
        currentTrackId = track.id
        
        // Build Now Playing info using type-safe builder
        var builder = NowPlayingInfoBuilder()
        builder.setTitle(track.title)
        builder.setArtist(track.artistName)
        builder.setPlaybackRate(isPlaying ? 1.0 : 0.0)
        builder.setElapsedPlaybackTime(currentTime)
        builder.setMediaType(1) // Audio
        
        if let albumTitle = track.albumTitle {
            builder.setAlbumTitle(albumTitle)
        }
        
        builder.setPlaybackDuration(duration)
        
        // Queue info
        builder.setQueueCount(queueCount)
        if let queueIndex = queueIndex {
            builder.setQueueIndex(queueIndex)
        }
        
        // Use cached artwork if available and track hasn't changed
        if !trackChanged, let cachedArtwork = artworkCache[track.id] {
            builder.setArtwork(cachedArtwork)
        }
        
        // Apply update on main actor - build dictionary to avoid capture issues
        let infoToApply = builder.build()
        await MainActor.run {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = infoToApply
        }
        
        return updateId
    }
    
    /// Update playback state (playing/paused)
    /// - Parameters:
    ///   - isPlaying: Whether playback is active
    ///   - currentTime: Current playback time
    ///   - trackId: Current track ID for validation
    /// - Returns: true if update was applied, false if track changed
    func updatePlaybackState(isPlaying: Bool, currentTime: TimeInterval, trackId: String?) async -> Bool {
        // Validate track hasn't changed
        guard currentTrackId == trackId else {
            logger.debug("updatePlaybackState: Track changed, ignoring update")
            return false
        }
        
        await MainActor.run {
            var builder = NowPlayingInfoBuilder()
            builder.merge(existing: MPNowPlayingInfoCenter.default().nowPlayingInfo)
            // Update playback state
            builder.setPlaybackRate(isPlaying ? 1.0 : 0.0)
            builder.setElapsedPlaybackTime(currentTime)
            MPNowPlayingInfoCenter.default().nowPlayingInfo = builder.build()
        }
        
        return true
    }
    
    /// Update playback time
    /// - Parameters:
    ///   - currentTime: Current playback time
    ///   - duration: Track duration
    ///   - trackId: Current track ID for validation
    /// - Returns: true if update was applied, false if track changed
    func updatePlaybackTime(currentTime: TimeInterval, duration: TimeInterval, trackId: String?) async -> Bool {
        // Validate track hasn't changed
        guard currentTrackId == trackId else {
            return false
        }
        
        await MainActor.run {
            var builder = NowPlayingInfoBuilder()
            builder.merge(existing: MPNowPlayingInfoCenter.default().nowPlayingInfo)
            // Update time and duration
            builder.setElapsedPlaybackTime(currentTime)
            builder.setPlaybackDuration(duration)
            MPNowPlayingInfoCenter.default().nowPlayingInfo = builder.build()
        }
        
        return true
    }
    
    /// Update queue info
    /// - Parameters:
    ///   - queueCount: Number of tracks in queue
    ///   - queueIndex: Current index in queue
    ///   - trackId: Current track ID for validation
    /// - Returns: true if update was applied, false if track changed
    func updateQueueInfo(queueCount: Int, queueIndex: Int?, trackId: String?) async -> Bool {
        // Validate track hasn't changed
        guard currentTrackId == trackId else {
            return false
        }
        
        await MainActor.run {
            var builder = NowPlayingInfoBuilder()
            builder.merge(existing: MPNowPlayingInfoCenter.default().nowPlayingInfo)
            // Update queue info
            builder.setQueueCount(queueCount)
            if let queueIndex = queueIndex {
                builder.setQueueIndex(queueIndex)
            }
            MPNowPlayingInfoCenter.default().nowPlayingInfo = builder.build()
        }
        
        return true
    }
    
    // MARK: - Artwork Management
    
    /// Update artwork for current track
    /// - Parameters:
    ///   - artwork: The artwork to set
    ///   - trackId: Track ID for validation
    ///   - artworkRequestId: Request ID for validation
    /// - Returns: true if update was applied
    func updateArtwork(artwork: MPMediaItemArtwork, trackId: String, artworkRequestId: Int) async -> Bool {
        // Validate this is still the current track and latest request
        guard currentTrackId == trackId,
              artworkRequestId == self.artworkRequestId else {
            logger.debug("updateArtwork: Track or request changed, ignoring artwork")
            return false
        }
        
        // Cache artwork
        artworkCache[trackId] = artwork
        
        // Update Now Playing info
        await MainActor.run {
            var builder = NowPlayingInfoBuilder()
            builder.merge(existing: MPNowPlayingInfoCenter.default().nowPlayingInfo)
            // Update artwork
            builder.setArtwork(artwork)
            MPNowPlayingInfoCenter.default().nowPlayingInfo = builder.build()
        }
        
        return true
    }
    
    /// Get artwork request ID for tracking
    func getArtworkRequestId() -> Int {
        artworkRequestId += 1
        return artworkRequestId
    }
    
    /// Check if artwork is cached
    func getCachedArtwork(trackId: String) -> MPMediaItemArtwork? {
        return artworkCache[trackId]
    }
    
    /// Clear Now Playing info
    func clear() async {
        currentTrackId = nil
        await MainActor.run {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        }
    }
    
    /// Get current track ID (for validation)
    func getCurrentTrackId() -> String? {
        return currentTrackId
    }
}

