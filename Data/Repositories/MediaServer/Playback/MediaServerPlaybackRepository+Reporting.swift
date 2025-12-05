
import Foundation

extension MediaServerPlaybackRepository {
    func startProgressReporting() {
        // Cancel any existing progress reporting
        progressReportingTask?.cancel()
        
        progressReportingTask = Task { @MainActor [weak self] in
            guard let self = self else { return }
            
            // Report progress every 10 seconds
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 10_000_000_000) // 10 seconds
                
                guard !Task.isCancelled,
                      let itemId = self.currentItemId,
                      let playSessionId = self.currentPlaySessionId,
                      let mediaSourceId = self.currentMediaSourceId else {
                    break
                }
                
                let position = await self.getCurrentTime()
                let positionTicks = Int64(position * 10_000_000)
                
                try? await self.apiClient.reportPlaybackProgress(
                    itemId: itemId,
                    mediaSourceId: mediaSourceId,
                    playSessionId: playSessionId,
                    positionTicks: positionTicks,
                    isPaused: self.isPaused,
                    eventName: "timeupdate"
                )
            }
        }
    }
    
    func reportPlaybackStart(itemId: String, playSessionId: String, playMethod: String) async {
        let positionTicks: Int64 = 0 // Starting at beginning
        try? await apiClient.reportPlaybackStart(
            itemId: itemId,
            mediaSourceId: currentMediaSourceId,
            playSessionId: playSessionId,
            positionTicks: positionTicks,
            isPaused: false,
            playMethod: playMethod
        )
        
        // Start progress reporting
        startProgressReporting()
    }
}

