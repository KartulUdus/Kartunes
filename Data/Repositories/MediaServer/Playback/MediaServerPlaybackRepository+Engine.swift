
import Foundation
import AVFoundation

extension MediaServerPlaybackRepository {
    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        if keyPath == "status" {
            if let item = object as? AVPlayerItem {
                switch item.status {
                case .readyToPlay:
                    logger.debug("Playback: player item ready to play")
                    // Update state when ready
                    Task {
                        await MainActor.run {
                            // Notify that playback can start
                        }
                    }
                case .failed:
                    if let error = item.error {
                        logger.error("Playback: player item failed – \(error.localizedDescription)")
                        if let nsError = error as NSError? {
                            logger.debug("Playback: error domain: \(nsError.domain), code: \(nsError.code)")
                            logger.debug("Playback: user info: \(nsError.userInfo)")
                        }
                        // Log the asset URL to help debug
                        if let asset = item.asset as? AVURLAsset {
                            logger.debug("Playback: failed URL: \(asset.url.absoluteString)")
                        }
                    } else {
                        logger.error("Playback: player item failed – Unknown error")
                    }
                case .unknown:
                    logger.debug("Playback: player item status unknown")
                @unknown default:
                    break
                }
            }
        } else if keyPath == "rate" {
            // Rate changes indicate play/pause state
            if let player = object as? AVQueuePlayer {
                logger.debug("Playback: player rate changed: \(player.rate) (1.0 = playing, 0.0 = paused)")
            }
        } else {
            super.observeValue(forKeyPath: keyPath, of: object, change: change, context: context)
        }
    }
    
    @objc func playerItemFailed(_ notification: Notification) {
        if let error = notification.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error {
            logger.error("Playback: playback error – \(error.localizedDescription)")
            
            // Check for 404 error
            if let nsError = error as NSError? {
                if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorFileDoesNotExist {
                    // Try to get track ID from current item
                    if let itemId = currentItemId {
                        Task {
                            await handleTrackNotFound(trackId: itemId)
                        }
                    }
                }
            }
        }
    }
    
    @objc func playerItemDidPlayToEnd(_ notification: Notification) {
        // Track finished - let the ViewModel handle queue advancement
        // The ViewModel's observer will handle this via handleTrackFinished()
        // This prevents double-advancement and ensures queue state stays in sync
        logger.info("Playback: track finished, ViewModel will handle queue advancement")
        
        // Report stop for finished track
        let itemId = currentItemId
        let playSessionId = currentPlaySessionId
        let mediaSourceId = currentMediaSourceId
        
        Task { @MainActor [weak self] in
            guard let self = self,
                  let itemId = itemId,
                  let playSessionId = playSessionId,
                  let mediaSourceId = mediaSourceId else { return }
            
            // Get duration for final position
            let duration = await self.getDuration() ?? 0
            let positionTicks = Int64(duration * 10_000_000)
            try? await self.apiClient.reportPlaybackStopped(
                itemId: itemId,
                mediaSourceId: mediaSourceId,
                playSessionId: playSessionId,
                positionTicks: positionTicks,
                nextMediaType: "Audio"
            )
        }
        
        // Cancel progress reporting for this track
        progressReportingTask?.cancel()
        progressReportingTask = nil
        
        // Prefetch more items when a track finishes
        currentIndex += 1
        if currentIndex < currentQueue.count {
            startPrefetching(from: currentIndex)
        }
    }
    
    @objc func playerItemError(_ notification: Notification) {
        if let errorLog = notification.object as? AVPlayerItemErrorLog {
            logger.debug("Playback: player item error log entries: \(errorLog.events.count)")
            for event in errorLog.events {
                logger.debug("Playback: error: \(event.errorComment ?? "Unknown")")
            }
        }
    }
    
    @objc func playerItemWillPlay(_ notification: Notification) {
        // This is a placeholder - we'll use a different mechanism
    }
    
    func setupNotificationObservers() {
        // Observe player errors
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(playerItemFailed(_:)),
            name: .AVPlayerItemFailedToPlayToEndTime,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(playerItemDidPlayToEnd(_:)),
            name: .AVPlayerItemDidPlayToEndTime,
            object: nil
        )
        
        // Observe item errors
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(playerItemError(_:)),
            name: .AVPlayerItemNewErrorLogEntry,
            object: nil
        )
        
        // Observe rate changes to track playing state
        player?.addObserver(self, forKeyPath: "rate", options: [.new], context: nil)
        
        // Observe when items are about to play to prefetch more
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(playerItemWillPlay(_:)),
            name: .AVPlayerItemNewErrorLogEntry, // We'll use a different approach
            object: nil
        )
    }
    
    func removeNotificationObservers() {
        if let oldPlayer = player {
            // Remove KVO observer for rate
            oldPlayer.removeObserver(self, forKeyPath: "rate")
            // Remove old player items' observers
            let oldItems = oldPlayer.items()
            for oldItem in oldItems {
                oldItem.removeObserver(self, forKeyPath: "status")
            }
            // Remove notification observers
            NotificationCenter.default.removeObserver(self)
        }
    }
}

