import Intents
import Foundation

/// Handles INPlayMediaIntent requests from Siri
final class PlayMediaIntentHandler: NSObject, INPlayMediaIntentHandling {
    
    private let catalogService = MediaCatalogService()
    private let requestManager = SiriPlaybackRequestManager()
    
    // MARK: - INPlayMediaIntentHandling
    
    /// Resolve media items from the intent
    func resolveMediaItems(for intent: INPlayMediaIntent, with completion: @escaping ([INPlayMediaMediaItemResolutionResult]) -> Void) {
        // If mediaItems are already provided, use them
        if let mediaItems = intent.mediaItems, !mediaItems.isEmpty {
            // Convert array of media items to array of resolution results
            let results = mediaItems.map { INPlayMediaMediaItemResolutionResult.success(with: $0) }
            completion(results)
            return
        }
        
        // Otherwise, try to resolve from mediaSearch
        guard let mediaSearch = intent.mediaSearch else {
            completion([.needsValue()])
            return
        }
        
        // Extract search parameters
        let mediaType = mediaSearch.mediaType
        let mediaName = mediaSearch.mediaName
        let artistName = mediaSearch.artistName
        let albumName = mediaSearch.albumName
        
        // Determine what we're searching for
        Task {
            let results: [INMediaItem]
            
            switch mediaType {
            case .artist:
                // Search for artists
                if let name = mediaName ?? artistName {
                    let artists = await catalogService.searchArtists(named: name)
                    results = artists.prefix(5).map { artist in
                        INMediaItem(
                            identifier: artist.id,
                            title: artist.name,
                            type: .artist,
                            artwork: nil,
                            artist: artist.name
                        )
                    }
                } else {
                    results = []
                }
                
            case .album:
                // Search for albums
                if let name = mediaName ?? albumName {
                    let albums = await catalogService.searchAlbums(named: name, byArtist: artistName)
                    results = albums.prefix(5).map { album in
                        INMediaItem(
                            identifier: album.id,
                            title: album.title,
                            type: .album,
                            artwork: nil,
                            artist: album.artistName
                        )
                    }
                } else {
                    results = []
                }
                
            case .song, .music:
                // Search for tracks
                if let name = mediaName {
                    let tracks = await catalogService.searchTracks(named: name, byArtist: artistName)
                    results = tracks.prefix(5).map { track in
                        INMediaItem(
                            identifier: track.id,
                            title: track.title,
                            type: .song,
                            artwork: nil,
                            artist: track.artistName
                        )
                    }
                } else {
                    results = []
                }
                
            case .playlist:
                // Search for playlists
                if let name = mediaName {
                    let playlists = await catalogService.searchPlaylists(named: name)
                    results = playlists.prefix(5).map { playlist in
                        INMediaItem(
                            identifier: playlist.id,
                            title: playlist.name,
                            type: .playlist,
                            artwork: nil,
                            artist: nil
                        )
                    }
                } else {
                    results = []
                }
                
            default:
                results = []
            }
            
            // Return results
            if results.isEmpty {
                completion([.unsupported()])
            } else if results.count == 1 {
                completion([.success(with: results[0])])
            } else {
                // Multiple results - Siri will handle disambiguation
                completion([.disambiguation(with: results)])
            }
        }
    }
    
    /// Handle the intent once resolved
    func handle(intent: INPlayMediaIntent, completion: @escaping (INPlayMediaIntentResponse) -> Void) {
        guard let mediaItems = intent.mediaItems, !mediaItems.isEmpty else {
            let response = INPlayMediaIntentResponse(code: .failure, userActivity: nil)
            completion(response)
            return
        }
        
        // Extract shuffle preference
        let shuffle = intent.playShuffled ?? false
        
        // Determine the type and ID from the first media item
        let firstItem = mediaItems[0]
        let requestType: SiriPlaybackRequestType
        
        switch firstItem.type {
        case .artist:
            requestType = .artist(id: firstItem.identifier ?? "")
        case .album:
            requestType = .album(id: firstItem.identifier ?? "")
        case .song, .music:
            requestType = .track(id: firstItem.identifier ?? "")
        case .playlist:
            requestType = .playlist(id: firstItem.identifier ?? "")
        default:
            // Fallback to track
            requestType = .track(id: firstItem.identifier ?? "")
        }
        
        // Create and save the playback request
        let request = SiriPlaybackRequest(type: requestType, shuffle: shuffle)
        requestManager.saveRequest(request)
        
        // Return handleInApp to launch the app
        let response = INPlayMediaIntentResponse(code: .handleInApp, userActivity: nil)
        completion(response)
    }
}

