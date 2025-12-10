import Foundation

enum MediaServerLibraryFetcher {
    static func fetchFullLibrary(
        apiClient: MediaServerAPIClient,
        logger: AppLogger,
        progressCallback: @Sendable @escaping (SyncProgress) -> Void
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
            let updateInterval = 0.3
            while isFetching {
                try? await Task.sleep(nanoseconds: UInt64(updateInterval * 1_000_000_000))
                guard isFetching else { break }
                
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
