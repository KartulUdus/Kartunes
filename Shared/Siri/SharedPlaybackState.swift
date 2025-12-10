import Foundation
import Intents

/// Manages shared playback state between the Intents Extension and main app via App Group
final class SharedPlaybackState {
    private static let appGroupIdentifier = "group.com.kartul.kartunes"
    private static let suite: UserDefaults? = UserDefaults(suiteName: appGroupIdentifier)
    
    // Keys
    private static let currentTrackIdKey = "currentTrackId"
    private static let currentTrackTitleKey = "currentTrackTitle"
    private static let currentTrackArtistKey = "currentTrackArtist"
    private static let pendingLikeTrackIdKey = "pendingLikeTrackId"
    private static let pendingLikeIsLikeKey = "pendingLikeIsLike"
    
    /// Store the currently playing track
    static func storeCurrentTrack(_ track: Track) {
        guard let suite = suite else {
            NSLog("SharedPlaybackState: Failed to access App Group UserDefaults")
            return
        }
        
        suite.set(track.id, forKey: currentTrackIdKey)
        suite.set(track.title, forKey: currentTrackTitleKey)
        suite.set(track.artistName, forKey: currentTrackArtistKey)
        suite.synchronize()
    }
    
    /// Load the current track ID
    static func loadCurrentTrackId() -> String? {
        return suite?.string(forKey: currentTrackIdKey)
    }
    
    /// Load current track info as INMediaItem (for extension use)
    static func loadCurrentTrackAsINMediaItem() -> INMediaItem? {
        guard let suite = suite,
              let trackId = suite.string(forKey: currentTrackIdKey),
              let title = suite.string(forKey: currentTrackTitleKey) else {
            return nil
        }
        
        let artist = suite.string(forKey: currentTrackArtistKey)
        
        return INMediaItem(
            identifier: trackId,
            title: title,
            type: .song,
            artwork: nil,
            artist: artist
        )
    }
    
    /// Request a like/unlike change for a track
    static func requestLikeChange(trackId: String, isLike: Bool) {
        guard let suite = suite else {
            NSLog("SharedPlaybackState: Failed to access App Group UserDefaults")
            return
        }
        
        suite.set(trackId, forKey: pendingLikeTrackIdKey)
        suite.set(isLike, forKey: pendingLikeIsLikeKey)
        suite.synchronize()
    }
    
    /// Consume and return a pending like request (removes it after reading)
    static func consumePendingLikeRequest() -> (trackId: String, isLike: Bool)? {
        guard let suite = suite,
              let trackId = suite.string(forKey: pendingLikeTrackIdKey) else {
            return nil
        }
        
        let isLike = suite.bool(forKey: pendingLikeIsLikeKey)
        
        // Clear the request after reading
        suite.removeObject(forKey: pendingLikeTrackIdKey)
        suite.removeObject(forKey: pendingLikeIsLikeKey)
        suite.synchronize()
        
        return (trackId, isLike)
    }
}

