
import Foundation
import Combine
import WatchKit

@MainActor
final class WatchPlaybackViewModel: ObservableObject {
    @Published var trackTitle: String = ""
    @Published var trackArtist: String = ""
    @Published var isPlaying: Bool = false
    @Published var isFavourite: Bool = false
    @Published var hasTrack: Bool = false
    @Published var isConnected: Bool = false
    @Published var albumArtURL: URL?
    @Published var currentPosition: TimeInterval = 0
    
    private var currentTrackId: String?
    
    let session: WatchPlaybackSession
    
    init(session: WatchPlaybackSession) {
        self.session = session
        session.viewModel = self
    }
    
    // MARK: - Actions
    
    func playPauseTapped() {
        session.sendPlayPause()
    }
    
    func nextTapped() {
        session.sendNext()
    }
    
    func previousTapped() {
        // If less than 5 seconds in, go to previous song, otherwise restart current song
        if currentPosition < 5.0 {
            session.sendPrevious()
        } else {
            session.sendSeek(to: 0)
        }
    }
    
    func toggleFavourite() {
        session.sendToggleFavourite()
    }
    
    func radioTapped() {
        session.sendRadioFromCurrentTrack()
        // Provide haptic feedback
        WKInterfaceDevice.current().play(.click)
    }
    
    // MARK: - State Updates
    
    func updateState(_ state: WatchStateMessage) {
        if let track = state.track {
            // Check if track changed (by ID) to force album art update
            let trackChanged = track.id != (currentTrackId ?? "")
            currentTrackId = track.id
            
            trackTitle = track.title
            trackArtist = track.artist
            isFavourite = track.isFavourite
            hasTrack = true
            
            // Always update album art URL when track changes or URL is different
            let newAlbumArtURL = track.albumArtURL.flatMap { URL(string: $0) }
            if trackChanged || albumArtURL != newAlbumArtURL {
                albumArtURL = newAlbumArtURL
            }
        } else {
            trackTitle = ""
            trackArtist = ""
            isFavourite = false
            hasTrack = false
            albumArtURL = nil
            currentTrackId = nil
        }
        
        // Always update playback state
        let newIsPlaying = state.playbackState == .playing
        if isPlaying != newIsPlaying {
            isPlaying = newIsPlaying
        }
        
        // Update current position
        currentPosition = state.position
        
        isConnected = true
    }
}

