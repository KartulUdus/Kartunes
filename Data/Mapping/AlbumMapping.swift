
import Foundation

extension Album {
    /// Creates an Album domain entity from a JellyfinAlbumDTO
    init(
        dto: JellyfinAlbumDTO,
        apiClient: MediaServerAPIClient
    ) {
        // Build image URL with tag if available (better caching, especially for Emby)
        let thumbnailURL = apiClient.buildImageURL(
            forItemId: dto.id,
            imageType: "Primary",
            maxWidth: 300,
            tag: dto.primaryImageTag
        )
        
        self.init(
            id: dto.id,
            title: dto.name,
            artistName: dto.artistName ?? "Unknown Artist",
            thumbnailURL: thumbnailURL,
            year: dto.productionYear
        )
    }
}

