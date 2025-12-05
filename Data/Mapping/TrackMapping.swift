
import Foundation

extension Track {
    /// Creates a Track domain entity from a JellyfinTrackDTO
    init(
        dto: JellyfinTrackDTO,
        serverId: UUID,
        apiClient: MediaServerAPIClient,
        isLiked: Bool? = nil
    ) {
        // Convert runTimeTicks to TimeInterval
        let ticks = dto.runTimeTicks ?? 0
        let durationSeconds: TimeInterval
        if ticks > 0 {
            let calculated = TimeInterval(ticks) / 10_000_000.0
            durationSeconds = calculated.isNaN || calculated.isInfinite ? 0 : calculated
        } else {
            durationSeconds = 0
        }
        
        // Parse dateAdded from ISO8601 string
        let dateAdded: Date?
        if let dateString = dto.dateAdded, !dateString.isEmpty {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            var date = formatter.date(from: dateString)
            if date == nil {
                formatter.formatOptions = [.withInternetDateTime]
                date = formatter.date(from: dateString)
            }
            dateAdded = date
        } else {
            dateAdded = nil
        }
        
        // Determine isLiked: use provided value, fall back to DTO userData, then false
        let liked = isLiked ?? dto.userData?.isFavorite ?? false
        
        self.init(
            id: dto.id,
            title: dto.name,
            albumId: dto.albumId,
            albumTitle: dto.album,
            artistName: dto.artists?.first ?? "Unknown Artist",
            duration: durationSeconds,
            trackNumber: dto.indexNumber,
            discNumber: dto.discNumber,
            dateAdded: dateAdded,
            playCount: dto.playCount ?? 0,
            isLiked: liked,
            streamUrl: apiClient.buildStreamURL(forTrackId: dto.id),
            serverId: serverId
        )
    }
}

