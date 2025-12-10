import Intents
import Foundation

/// Handles INPlayMediaIntent requests from Siri
final class PlayMediaIntentHandler: NSObject, INPlayMediaIntentHandling {
    
    private let catalogService = MediaCatalogService()
    private let requestManager = SiriPlaybackRequestManager()
    private let logger = Log.make(.siri)
    
    override init() {
        super.init()
        NSLog("🟢 PlayMediaIntentHandler: Initialized")
        print("🟢 [SIRI] PlayMediaIntentHandler: Initialized")
        logger.info("PlayMediaIntentHandler initialized")
        
        // Test that services are accessible
        _ = catalogService
        _ = requestManager
        NSLog("🟢 PlayMediaIntentHandler: Services initialized successfully")
        print("🟢 [SIRI] PlayMediaIntentHandler: Services initialized successfully")
    }
    
    // MARK: - INPlayMediaIntentHandling
    
    /// Resolve media items from the intent
    func resolveMediaItems(for intent: INPlayMediaIntent, with completion: @escaping ([INPlayMediaMediaItemResolutionResult]) -> Void) {
        NSLog("🟢 PlayMediaIntentHandler: resolveMediaItems called")
        print("🟢 [SIRI] PlayMediaIntentHandler: resolveMediaItems called")
        logger.info("resolveMediaItems called")
        // If mediaItems are already provided, use them
        if let mediaItems = intent.mediaItems, !mediaItems.isEmpty {
            NSLog("🟢 PlayMediaIntentHandler: Media items already provided: \(mediaItems.count)")
            print("🟢 [SIRI] PlayMediaIntentHandler: Media items already provided: \(mediaItems.count)")
            logger.info("Media items already provided: \(mediaItems.count)")
            // Convert array of media items to array of resolution results
            let results = mediaItems.map { INPlayMediaMediaItemResolutionResult.success(with: $0) }
            completion(results)
            return
        }
        
        // Otherwise, try to resolve from mediaSearch
        guard let mediaSearch = intent.mediaSearch else {
            NSLog("🟢 PlayMediaIntentHandler: No mediaSearch found, returning needsValue")
            print("🟢 [SIRI] PlayMediaIntentHandler: No mediaSearch found, returning needsValue")
            logger.warning("No mediaSearch found in intent")
            completion([.needsValue()])
            return
        }
        
        // Extract search parameters
        let mediaType = mediaSearch.mediaType
        let mediaName = mediaSearch.mediaName
        let artistName = mediaSearch.artistName
        let albumName = mediaSearch.albumName
        
        NSLog("🟢 PlayMediaIntentHandler: Searching - type: \(mediaType.rawValue), name: \(mediaName ?? "nil"), artist: \(artistName ?? "nil"), album: \(albumName ?? "nil")")
        print("🟢 [SIRI] PlayMediaIntentHandler: Searching - type: \(mediaType.rawValue), name: \(mediaName ?? "nil"), artist: \(artistName ?? "nil"), album: \(albumName ?? "nil")")
        logger.info("Searching - type: \(mediaType.rawValue), name: \(String(describing: mediaName)), artist: \(String(describing: artistName)), album: \(String(describing: albumName))")
        
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
            NSLog("🟢 PlayMediaIntentHandler: Found \(results.count) results")
            print("🟢 [SIRI] PlayMediaIntentHandler: Found \(results.count) results")
            logger.info("Found \(results.count) search results")
            
            if results.isEmpty {
                NSLog("🟢 PlayMediaIntentHandler: No results, returning unsupported")
                print("🟢 [SIRI] PlayMediaIntentHandler: No results, returning unsupported")
                logger.warning("No search results found")
                completion([.unsupported()])
            } else if results.count == 1 {
                NSLog("🟢 PlayMediaIntentHandler: Single result found: \(results[0].title ?? "unknown")")
                print("🟢 [SIRI] PlayMediaIntentHandler: Single result found: \(results[0].title ?? "unknown")")
                logger.info("Single result: \(results[0].title ?? "unknown")")
                completion([.success(with: results[0])])
            } else {
                // Multiple results - Siri will handle disambiguation
                NSLog("🟢 PlayMediaIntentHandler: Multiple results, returning disambiguation")
                print("🟢 [SIRI] PlayMediaIntentHandler: Multiple results, returning disambiguation")
                logger.info("Multiple results, returning disambiguation")
                completion([.disambiguation(with: results)])
            }
        }
    }
    
    /// Handle the intent once resolved
    func handle(intent: INPlayMediaIntent, completion: @escaping (INPlayMediaIntentResponse) -> Void) {
        NSLog("🟢 PlayMediaIntentHandler: handle() called")
        print("🟢 [SIRI] PlayMediaIntentHandler: handle() called")
        logger.info("handle() called")
        
        guard let mediaItems = intent.mediaItems, !mediaItems.isEmpty else {
            NSLog("🟢 PlayMediaIntentHandler: No media items, returning failure")
            print("🟢 [SIRI] PlayMediaIntentHandler: No media items, returning failure")
            logger.error("No media items in intent")
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
        NSLog("🟢 PlayMediaIntentHandler: Saving playback request: \(request)")
        print("🟢 [SIRI] PlayMediaIntentHandler: Saving playback request: \(request)")
        logger.info("Saving playback request: type=\(requestType), shuffle=\(shuffle)")
        requestManager.saveRequest(request)
        
        // Return handleInApp to launch the app
        NSLog("🟢 PlayMediaIntentHandler: Returning handleInApp response")
        print("🟢 [SIRI] PlayMediaIntentHandler: Returning handleInApp response")
        logger.info("Returning handleInApp response")
        let response = INPlayMediaIntentResponse(code: .handleInApp, userActivity: nil)
        completion(response)
    }
}

