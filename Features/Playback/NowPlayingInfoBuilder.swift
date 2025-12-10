
import Foundation
import MediaPlayer

/// Type-safe builder for MPNowPlayingInfoCenter dictionaries
/// Provides compile-time safety for Now Playing info properties
/// Safe to use from any context (value type with no actor isolation)
struct NowPlayingInfoBuilder: @unchecked Sendable {
    @preconcurrency private var info: [String: Any] = [:]
    
    // MARK: - Track Info
    
    mutating func setTitle(_ title: String) {
        info[MPMediaItemPropertyTitle] = title
    }
    
    mutating func setArtist(_ artist: String) {
        info[MPMediaItemPropertyArtist] = artist
    }
    
    mutating func setAlbumTitle(_ albumTitle: String) {
        info[MPMediaItemPropertyAlbumTitle] = albumTitle
    }
    
    // MARK: - Playback State
    
    mutating func setPlaybackRate(_ rate: Double) {
        info[MPNowPlayingInfoPropertyPlaybackRate] = rate
    }
    
    mutating func setElapsedPlaybackTime(_ time: TimeInterval) {
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = time
    }
    
    mutating func setPlaybackDuration(_ duration: TimeInterval) {
        guard duration > 0 else { return }
        info[MPMediaItemPropertyPlaybackDuration] = duration
    }
    
    mutating func setMediaType(_ type: Int) {
        info[MPNowPlayingInfoPropertyMediaType] = type
    }
    
    // MARK: - Queue Info
    
    mutating func setQueueCount(_ count: Int) {
        guard count > 0 else { return }
        info[MPNowPlayingInfoPropertyPlaybackQueueCount] = count
    }
    
    mutating func setQueueIndex(_ index: Int) {
        info[MPNowPlayingInfoPropertyPlaybackQueueIndex] = index
    }
    
    // MARK: - Artwork
    
    mutating func setArtwork(_ artwork: MPMediaItemArtwork) {
        info[MPMediaItemPropertyArtwork] = artwork
    }
    
    // MARK: - Build
    
    /// Merges with existing info from MPNowPlayingInfoCenter
    mutating func merge(existing: [String: Any]?) {
        guard let existing = existing else { return }
        // Only merge properties we haven't explicitly set
        if info[MPMediaItemPropertyTitle] == nil,
           let title = existing[MPMediaItemPropertyTitle] as? String {
            info[MPMediaItemPropertyTitle] = title
        }
        if info[MPMediaItemPropertyArtist] == nil,
           let artist = existing[MPMediaItemPropertyArtist] as? String {
            info[MPMediaItemPropertyArtist] = artist
        }
        if info[MPMediaItemPropertyAlbumTitle] == nil,
           let albumTitle = existing[MPMediaItemPropertyAlbumTitle] as? String {
            info[MPMediaItemPropertyAlbumTitle] = albumTitle
        }
        if info[MPMediaItemPropertyArtwork] == nil,
           let artwork = existing[MPMediaItemPropertyArtwork] as? MPMediaItemArtwork {
            info[MPMediaItemPropertyArtwork] = artwork
        }
        if info[MPMediaItemPropertyPlaybackDuration] == nil,
           let duration = existing[MPMediaItemPropertyPlaybackDuration] as? TimeInterval {
            info[MPMediaItemPropertyPlaybackDuration] = duration
        }
        if info[MPNowPlayingInfoPropertyPlaybackQueueCount] == nil,
           let queueCount = existing[MPNowPlayingInfoPropertyPlaybackQueueCount] as? Int {
            info[MPNowPlayingInfoPropertyPlaybackQueueCount] = queueCount
        }
        if info[MPNowPlayingInfoPropertyPlaybackQueueIndex] == nil,
           let queueIndex = existing[MPNowPlayingInfoPropertyPlaybackQueueIndex] as? Int {
            info[MPNowPlayingInfoPropertyPlaybackQueueIndex] = queueIndex
        }
    }
    
    /// Builds the final dictionary for MPNowPlayingInfoCenter
    func build() -> [String: Any] {
        return info
    }
    
    /// Builds an empty dictionary (for clearing)
    static func empty() -> [String: Any] {
        return [:]
    }
}

