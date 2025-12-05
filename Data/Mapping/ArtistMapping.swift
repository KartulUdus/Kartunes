
import Foundation

extension Artist {
    /// Creates an Artist domain entity from a JellyfinArtistDTO
    init(
        dto: JellyfinArtistDTO,
        apiClient: MediaServerAPIClient
    ) {
        let thumbnailURL = apiClient.buildImageURL(
            forItemId: dto.id,
            imageType: "Primary",
            maxWidth: 300,
            tag: dto.primaryImageTag
        )
        
        self.init(
            id: dto.id,
            name: dto.name,
            thumbnailURL: thumbnailURL
        )
    }
}

