
import Foundation

/// A playback queue containing an ordered list of tracks with context
class PlaybackQueue {
    var tracks: [Track]
    var currentIndex: Int
    let context: PlaybackContext
    let timestamp: Date
    
    init(tracks: [Track], currentIndex: Int, context: PlaybackContext) {
        self.tracks = tracks
        self.currentIndex = max(0, min(currentIndex, tracks.count - 1))
        self.context = context
        self.timestamp = Date()
    }
    
    // MARK: - Derived Properties
    
    var currentTrack: Track? {
        guard currentIndex >= 0 && currentIndex < tracks.count else { return nil }
        return tracks[currentIndex]
    }
    
    var nextTrack: Track? {
        guard currentIndex + 1 < tracks.count else { return nil }
        return tracks[currentIndex + 1]
    }
    
    var previousTrack: Track? {
        guard currentIndex - 1 >= 0 else { return nil }
        return tracks[currentIndex - 1]
    }
    
    var hasNext: Bool {
        currentIndex + 1 < tracks.count
    }
    
    var hasPrevious: Bool {
        currentIndex > 0
    }
    
    // MARK: - Navigation
    
    func moveToNext() -> Bool {
        guard hasNext else { return false }
        currentIndex += 1
        return true
    }
    
    func moveToPrevious() -> Bool {
        guard hasPrevious else { return false }
        currentIndex -= 1
        return true
    }
    
    func skipTo(index: Int) -> Bool {
        guard index >= 0 && index < tracks.count else { return false }
        currentIndex = index
        return true
    }
}

