
import Foundation
import AVFoundation

extension MediaServerPlaybackRepository {
    func startPrefetching(from startIndex: Int) {
        // Cancel existing prefetch task
        prefetchTask?.cancel()
        
        prefetchTask = Task { [weak self] in
            guard let self = self else { return }
            
            // Prefetch next window of tracks
            let endIndex = min(startIndex + prefetchWindow, currentQueue.count)
            
            for trackIndex in startIndex..<endIndex {
                // Skip if already loaded
                if loadedItems.contains(trackIndex) {
                    continue
                }
                
                // Check if task was cancelled
                if Task.isCancelled {
                    return
                }
                
                guard trackIndex < currentQueue.count else { break }
                let track = currentQueue[trackIndex]
                
                logger.debug("Playback: prefetching track #\(trackIndex): \(track.title)")
                
                // Build stream URL
                // For Emby, always rebuild URLs to ensure we use direct streaming (HLS returns 400)
                // For Jellyfin, use cached URL if available, otherwise build new one
                let url: URL
                if apiClient.serverType == .emby {
                    // Always rebuild for Emby to ensure direct streaming (ignore cached HLS URLs)
                    url = await apiClient.buildStreamURL(forTrackId: track.id, useDirectStream: true)
                } else if let existingStreamUrl = track.streamUrl {
                    // For Jellyfin, use cached URL if available
                    url = existingStreamUrl
                } else {
                    url = await apiClient.buildStreamURL(forTrackId: track.id, useDirectStream: true)
                }
                
                // Create asset and item
                let asset = AVURLAsset(url: url)
                let item = AVPlayerItem(asset: asset)
                
                // Add observer
                item.addObserver(self, forKeyPath: "status", options: [.new], context: nil)
                
                // Add to player queue
                await MainActor.run {
                    if let player = self.player {
                        player.insert(item, after: player.items().last)
                        self.loadedItems.insert(trackIndex)
                        self.logger.debug("Playback: prefetched and added track #\(trackIndex) to queue")
                    }
                }
            }
        }
    }
}

