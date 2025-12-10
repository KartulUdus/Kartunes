
import Foundation
import AVFoundation

extension MediaServerPlaybackRepository {
    func pause() async {
        player?.pause()
        isPaused = true
        
        // Report pause event (skip for offline downloads)
        if currentPlaybackContext != .offlineDownloads,
           let itemId = currentItemId,
           let playSessionId = currentPlaySessionId,
           let mediaSourceId = currentMediaSourceId {
            let position = await getCurrentTime()
            let positionTicks = Int64(position * 10_000_000)
            Task {
                try? await apiClient.reportPlaybackProgress(
                    itemId: itemId,
                    mediaSourceId: mediaSourceId,
                    playSessionId: playSessionId,
                    positionTicks: positionTicks,
                    isPaused: true,
                    eventName: "pause"
                )
            }
        }
    }
    
    func resume() async {
        player?.play()
        isPaused = false
        
        // Report resume event (skip for offline downloads)
        if currentPlaybackContext != .offlineDownloads,
           let itemId = currentItemId,
           let playSessionId = currentPlaySessionId,
           let mediaSourceId = currentMediaSourceId {
            let position = await getCurrentTime()
            let positionTicks = Int64(position * 10_000_000)
            Task {
                try? await apiClient.reportPlaybackProgress(
                    itemId: itemId,
                    mediaSourceId: mediaSourceId,
                    playSessionId: playSessionId,
                    positionTicks: positionTicks,
                    isPaused: false,
                    eventName: "unpause"
                )
            }
        }
    }
    
    func stop() async {
        // Report stop for current track (skip for offline downloads)
        if currentPlaybackContext != .offlineDownloads,
           let itemId = currentItemId,
           let playSessionId = currentPlaySessionId,
           let mediaSourceId = currentMediaSourceId {
            let position = await getCurrentTime()
            let positionTicks = Int64(position * 10_000_000)
            Task {
                try? await apiClient.reportPlaybackStopped(
                    itemId: itemId,
                    mediaSourceId: mediaSourceId,
                    playSessionId: playSessionId,
                    positionTicks: positionTicks,
                    nextMediaType: nil
                )
            }
        }
        
        // Cancel progress reporting
        progressReportingTask?.cancel()
        progressReportingTask = nil
        
        // Cancel prefetch task
        prefetchTask?.cancel()
        prefetchTask = nil
        
        player?.pause()
        player?.removeAllItems()
        currentQueue = []
        currentIndex = 0
        loadedItems.removeAll()
        
        // Clear playback reporting state
        currentItemId = nil
        currentMediaSourceId = nil
        currentPlaySessionId = nil
        isPaused = false
        
        // Remove all observers
        removeNotificationObservers()
        player = nil
    }
    
    func seek(to time: TimeInterval) async {
        guard let player = player,
              let currentItem = player.currentItem,
              currentItem.status == .readyToPlay else { return }
        
        // Use a standard timescale for better compatibility
        let cmTime = CMTime(seconds: time, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        await player.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero)
        
        // Report seek event (skip for offline downloads)
        if currentPlaybackContext != .offlineDownloads,
           let itemId = currentItemId,
           let playSessionId = currentPlaySessionId,
           let mediaSourceId = currentMediaSourceId {
            let positionTicks = Int64(time * 10_000_000)
            Task {
                try? await apiClient.reportPlaybackProgress(
                    itemId: itemId,
                    mediaSourceId: mediaSourceId,
                    playSessionId: playSessionId,
                    positionTicks: positionTicks,
                    isPaused: isPaused,
                    eventName: "seek"
                )
            }
        }
    }
}

