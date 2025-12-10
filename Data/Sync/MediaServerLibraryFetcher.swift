
import Foundation

/// Handles fetching library data from the media server API
struct MediaServerLibraryFetcher {
    nonisolated let apiClient: MediaServerAPIClient
    nonisolated let logger: AppLogger
    
    nonisolated init(apiClient: MediaServerAPIClient, logger: AppLogger) {
        self.apiClient = apiClient
        self.logger = logger
    }
    
    /// Fetches all library data (artists, albums, tracks) with progress reporting
    func fetchFullLibrary(
        progressCallback: @escaping (SyncProgress) -> Void
    ) async throws -> ([JellyfinArtistDTO], [JellyfinAlbumDTO], [JellyfinTrackDTO]) {
        await MainActor.run {
            progressCallback(SyncProgress(progress: 0.0, stage: "Fetching artists and albums..."))
        }
        
        async let artistsTask = apiClient.fetchArtists()
        async let albumsTask = apiClient.fetchAlbums(byArtistId: nil)
        
        let (artistDTOs, albumDTOs) = try await (artistsTask, albumsTask)
        
        logger.info("Fetched \(artistDTOs.count) artists, \(albumDTOs.count) albums")
        
        let startTime = Date()
        var isFetching = true
        
        let trackFetchTask = Task {
            let tracks = try await apiClient.fetchTracks(byAlbumId: nil)
            isFetching = false
            return tracks
        }
        
        let progressTask = Task {
            let updateInterval = 0.3 // Update every 0.3 seconds
            
            while isFetching {
                try? await Task.sleep(nanoseconds: UInt64(updateInterval * 1_000_000_000))
                
                let stillFetching = isFetching
                guard stillFetching else { break }
                
                let elapsed = Date().timeIntervalSince(startTime)
                let estimatedDuration = 60.0
                let fetchProgress = min(0.28, 0.05 + (elapsed / estimatedDuration) * 0.23)
                
                await MainActor.run {
                    if isFetching {
                        progressCallback(SyncProgress(progress: fetchProgress, stage: "Fetching tracks from server..."))
                    }
                }
            }
        }
        
        let trackDTOs = try await trackFetchTask.value
        
        isFetching = false
        progressTask.cancel()
        
        await MainActor.run {
            progressCallback(SyncProgress(progress: 0.30, stage: "Processing artists..."))
        }
        
        logger.info("Fetched \(trackDTOs.count) tracks from server")
        logger.debug("Songs fetched from server - count: \(trackDTOs.count)")
        
        return (artistDTOs, albumDTOs, trackDTOs)
    }
}

