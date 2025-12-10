
import Foundation
@preconcurrency import CoreData

/// Coordinates playback requests from Siri
@MainActor
final class SiriPlaybackCoordinator {
    private let playbackViewModel: PlaybackViewModel
    private let libraryRepository: LibraryRepository
    private let logger = Log.make(.siri)
    
    init(playbackViewModel: PlaybackViewModel, libraryRepository: LibraryRepository) {
        self.playbackViewModel = playbackViewModel
        self.libraryRepository = libraryRepository
    }
    
    /// Handle a Siri playback request
    func handle(_ request: SiriPlaybackRequest) {
        logger.info("Handling Siri playback request: \(request)")
        
        Task {
            do {
                let tracks: [Track]
                
                switch request.type {
                case .artist(let artistId):
                    tracks = try await libraryRepository.fetchTracks(artistId: artistId)
                    logger.info("Fetched \(tracks.count) tracks for artist \(artistId)")
                    
                case .album(let albumId):
                    tracks = try await libraryRepository.fetchTracks(albumId: albumId)
                    logger.info("Fetched \(tracks.count) tracks for album \(albumId)")
                    
                case .track(let trackId):
                    // Find the track by ID using MediaCatalogService (direct Core Data lookup)
                    let catalogService = MediaCatalogService()
                    guard let track = await catalogService.findTrack(byId: trackId) else {
                        logger.warning("Track \(trackId) not found")
                        return
                    }
                    
                    // If we have an album, play the whole album starting from this track
                    if let albumId = track.albumId {
                        let albumTracks = try await libraryRepository.fetchTracks(albumId: albumId)
                        if let index = albumTracks.firstIndex(where: { $0.id == trackId }) {
                            tracks = albumTracks
                            // We'll start at this index
                            await MainActor.run {
                                startQueue(tracks: tracks, at: index, shuffle: request.shuffle, context: .album(albumId: albumId))
                            }
                            return
                        }
                    }
                    
                    // Fallback: just play this track
                    tracks = [track]
                    
                case .playlist(let playlistId):
                    tracks = try await libraryRepository.fetchPlaylistTracks(playlistId: playlistId)
                    logger.info("Fetched \(tracks.count) tracks for playlist \(playlistId)")
                }
                
                guard !tracks.isEmpty else {
                    logger.warning("No tracks found for request: \(request)")
                    return
                }
                
                // Determine context for proper queue management
                let context: PlaybackContext = {
                    switch request.type {
                    case .artist(let id):
                        return .artist(artistId: id)
                    case .album(let id):
                        return .album(albumId: id)
                    case .playlist(let id):
                        return .playlist(playlistId: id)
                    case .track:
                        return .custom(tracks.map { $0.id })
                    }
                }()
                
                startQueue(tracks: tracks, at: 0, shuffle: request.shuffle, context: context)
                
            } catch {
                logger.error("Failed to handle Siri playback request: \(error.localizedDescription)")
            }
        }
    }
    
    private func startQueue(tracks: [Track], at index: Int, shuffle: Bool, context: PlaybackContext) {
        // Set shuffle mode if requested
        if shuffle && !playbackViewModel.isShuffleEnabled {
            playbackViewModel.toggleShuffle()
        } else if !shuffle && playbackViewModel.isShuffleEnabled {
            playbackViewModel.toggleShuffle()
        }
        
        // Start the queue
        playbackViewModel.startQueue(from: tracks, at: index, context: context)
    }
}

