
import Foundation
import AVFoundation

extension MediaServerPlaybackRepository {
    func play(track: Track) async {
        await play(queue: [track], startingAt: 0, context: nil)
    }
    
    func play(queue: [Track], startingAt index: Int, context: PlaybackContext? = nil) async {
        // Stop previous track reporting if switching tracks
        // Don't report for offline downloads
        if currentPlaybackContext != .offlineDownloads,
           let previousItemId = currentItemId,
           let previousPlaySessionId = currentPlaySessionId,
           let previousMediaSourceId = currentMediaSourceId {
            // Report stop for previous track
            let previousPosition = await getCurrentTime()
            let positionTicks = Int64(previousPosition * 10_000_000) // Convert to 100-ns ticks
            Task {
                try? await apiClient.reportPlaybackStopped(
                    itemId: previousItemId,
                    mediaSourceId: previousMediaSourceId,
                    playSessionId: previousPlaySessionId,
                    positionTicks: positionTicks,
                    nextMediaType: "Audio"
                )
            }
        }
        
        // Cancel progress reporting for previous track
        progressReportingTask?.cancel()
        progressReportingTask = nil
        
        // Cancel any existing prefetch task
        prefetchTask?.cancel()
        prefetchTask = nil
        
        currentQueue = queue
        currentIndex = index
        currentPlaybackContext = context
        loadedItems.removeAll()
        guard index < queue.count else { return }
        
        let track = queue[index]
        currentItemId = track.id
        
        // Get playback info to extract MediaSourceId and PlaySessionId
        var mediaSourceId: String?
        var playSessionId: String?
        var playMethod = "DirectPlay"
        
        if let playbackInfo = try? await apiClient.getPlaybackInfo(itemId: track.id) {
            if let firstSource = playbackInfo.mediaSources?.first {
                mediaSourceId = firstSource.id
                
                // Determine play method based on source capabilities
                if firstSource.supportsDirectPlay == true {
                    playMethod = "DirectPlay"
                } else if firstSource.supportsDirectStream == true {
                    playMethod = "DirectStream"
                } else {
                    playMethod = "Transcode"
                }
            }
            
            // Use PlaySessionId from playback info if available, otherwise generate one
            playSessionId = playbackInfo.playSessionId ?? UUID().uuidString
        } else {
            // Generate a new play session ID if we can't get playback info
            playSessionId = UUID().uuidString
        }
        
        currentMediaSourceId = mediaSourceId
        currentPlaySessionId = playSessionId
        
        // Get access token and user ID for resource loader
        let accessToken = apiClient.accessToken ?? ""
        let userId = apiClient.userId
        
        // LAZY LOADING: Only build items for current track + prefetch window
        // This prevents hundreds of HTTP requests upfront
        let endIndex = min(index + prefetchWindow, queue.count)
        let tracksToLoad = Array(queue[index..<endIndex])
        
        logger.debug("Playback: lazy loading \(tracksToLoad.count) tracks (index \(index) to \(endIndex-1) of \(queue.count))")
        
        var items: [AVPlayerItem] = []
        items.reserveCapacity(tracksToLoad.count)
        
        for (offset, track) in tracksToLoad.enumerated() {
            let trackIndex = index + offset
            loadedItems.insert(trackIndex)
            
            // Check if we should use local file (for offline downloads)
            let url: URL
            if currentPlaybackContext == .offlineDownloads,
               OfflineDownloadManager.shared.isDownloaded(trackId: track.id) {
                // Use local file for offline downloads
                url = OfflineDownloadManager.shared.localFileURL(for: track.id)
                logger.debug("Playback: using local file for offline track \(trackIndex): \(track.title)")
            } else {
                // Build stream URL - prefer direct streaming when available (like FinAmp)
                // For Emby, always rebuild URLs to ensure we use direct streaming (HLS returns 400)
                // For Jellyfin, use cached URL if available, otherwise build new one
                if apiClient.serverType == .emby {
                    // Always rebuild for Emby to ensure direct streaming (ignore cached HLS URLs)
                    url = await apiClient.buildStreamURL(forTrackId: track.id, useDirectStream: true)
                } else if let existingStreamUrl = track.streamUrl {
                    // For Jellyfin, use cached URL if available
                    url = existingStreamUrl
                } else {
                    // Try to use direct streaming first (more efficient, faster startup)
                    // Falls back to HLS transcoding if direct streaming isn't available
                    url = await apiClient.buildStreamURL(forTrackId: track.id, useDirectStream: true)
                }
            }
            
            logger.debug("Playback: loaded stream URL for track \(trackIndex): \(track.title)")
            
            // Create AVURLAsset
            // For HLS (m3u8) and direct streaming with ApiKey query parameter,
            // AVPlayer handles authentication automatically via query params
            // No need for resource loader - AVPlayer will use the query params automatically
            let asset = AVURLAsset(url: url)
            
            // Only use resource loader for non-HLS streams that use custom scheme
            // HLS and direct streaming with ApiKey use query parameters which AVPlayer handles natively
            let isHLS = url.pathExtension.contains("m3u8")
            let isDirectStream = url.path.contains("/Items/") && url.path.contains("/File")
            
            if !isHLS && !isDirectStream && url.scheme == "jellyfin" && !accessToken.isEmpty {
                let loader = AuthenticatedAssetResourceLoader(accessToken: accessToken, userId: userId)
                
                // Set callback for 404 errors
                loader.onHTTPError = { [weak self] statusCode, requestURL in
                    if statusCode == 404 {
                        Task {
                            await self?.handleTrackNotFound(trackId: track.id)
                        }
                    }
                }
                
                asset.resourceLoader.setDelegate(loader, queue: DispatchQueue.global(qos: .userInitiated))
                // Keep reference to loader to prevent deallocation
                self.resourceLoader = loader
                logger.debug("Playback: using resource loader for custom scheme")
            } else {
                logger.debug("Playback: using native AVPlayer authentication (HLS or direct stream with ApiKey)")
            }
            
            let item = AVPlayerItem(asset: asset)
            
            // Observe item status changes
            item.addObserver(self, forKeyPath: "status", options: [.new], context: nil)
            
            items.append(item)
        }
        
        // Remove old player observers
        removeNotificationObservers()
        if let oldPlayer = player {
            oldPlayer.replaceCurrentItem(with: nil)
        }
        
        // Create player with only the loaded items
        player = AVQueuePlayer(items: items)
        
        // Start prefetching more items in the background
        startPrefetching(from: endIndex)
        
        // Setup notification observers
        setupNotificationObservers()
        
        // Wait for item to be ready before playing
        if let firstItem = items.first {
            logger.debug("Playback: waiting for player item to be ready... Current status: \(firstItem.status.rawValue)")
            // Check if already ready
            if firstItem.status == .readyToPlay {
                let startingTrack = queue[index]
                logger.info("Playback: started track '\(startingTrack.title)' (queue size: \(queue.count))")
                player?.play()
                
                // Report playback start
                if let itemId = currentItemId, let playSessionId = currentPlaySessionId {
                    await reportPlaybackStart(itemId: itemId, playSessionId: playSessionId, playMethod: playMethod)
                }
            } else if firstItem.status == .failed {
                logger.error("Playback: player item already failed – \(firstItem.error?.localizedDescription ?? "Unknown error")")
            } else {
                // Wait for ready status - use a timeout
                let capturedPlayMethod = playMethod
                var observer: NSKeyValueObservation?
                observer = firstItem.observe(\.status, options: [.new]) { [weak self] item, _ in
                    self?.logger.debug("Playback: player item status changed to: \(item.status.rawValue)")
                    if item.status == .readyToPlay {
                        let startingTrack = queue[index]
                        self?.logger.info("Playback: started track '\(startingTrack.title)' (queue size: \(queue.count))")
                        self?.player?.play()
                        
                        // Report playback start
                        Task { @MainActor [weak self] in
                            guard let self = self,
                                  let itemId = self.currentItemId,
                                  let playSessionId = self.currentPlaySessionId else { return }
                            await self.reportPlaybackStart(itemId: itemId, playSessionId: playSessionId, playMethod: capturedPlayMethod)
                        }
                        
                        observer?.invalidate()
                    } else if item.status == .failed {
                        let errorDescription = item.error?.localizedDescription ?? "Unknown error"
                        self?.logger.error("Playback: player item failed – \(errorDescription)")
                        if let asset = item.asset as? AVURLAsset {
                            self?.logger.debug("Playback: failed URL: \(asset.url.absoluteString)")
                        }
                        if let error = item.error as NSError? {
                            self?.logger.debug("Playback: error domain: \(error.domain), code: \(error.code)")
                            
                            // Check for 404 error - check error code and userInfo
                            let is404 = error.code == NSURLErrorFileDoesNotExist ||
                                       (error.userInfo[NSLocalizedDescriptionKey] as? String)?.contains("404") == true ||
                                       error.code == 404
                            
                            if is404 {
                                Task { [weak self] in
                                    guard let self = self, index < queue.count else { return }
                                    await self.handleTrackNotFound(trackId: queue[index].id)
                                }
                            }
                        }
                        observer?.invalidate()
                    }
                }
                
                // Timeout after 10 seconds
                DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
                    guard let self = self else { return }
                    if firstItem.status != .readyToPlay && firstItem.status != .failed {
                        self.logger.warning("Playback: player item still not ready after 10 seconds, attempting to play anyway")
                        self.player?.play()
                    }
                    observer?.invalidate()
                }
            }
        } else {
            // Fallback: try to play immediately
            logger.warning("Playback: no items to play")
        }
    }
    
    func next() async {
        guard currentIndex < currentQueue.count - 1 else { return }
        
        currentIndex += 1
        
        // If the next track isn't loaded yet, we need to load it
        if !loadedItems.contains(currentIndex) {
            // Load from this index (will load current + prefetch window)
            await play(queue: currentQueue, startingAt: currentIndex)
        } else {
            // Just advance the player
            player?.advanceToNextItem()
        }
        
        // Prefetch more ahead if needed
        startPrefetching(from: currentIndex + 1)
    }
    
    /// Skip to a specific track index in the queue
    func skipTo(index: Int) async {
        guard index >= 0, index < currentQueue.count else { return }
        
        // If jumping far ahead, we may need to load the track
        if !loadedItems.contains(index) {
            // Load from this index
            await play(queue: currentQueue, startingAt: index)
        } else {
            // Find the item in the player queue and advance to it
            // For simplicity, just rebuild from this index
            await play(queue: currentQueue, startingAt: index)
        }
    }
    
    func previous() async {
        guard currentIndex > 0 else { return }
        await play(queue: currentQueue, startingAt: currentIndex - 1)
    }
}

