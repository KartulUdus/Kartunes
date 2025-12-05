
import Foundation

extension Playlist {
    /// Creates a Playlist domain entity from a JellyfinPlaylistDTO
    init(
        dto: JellyfinPlaylistDTO,
        serverType: MediaServerType
    ) {
        self.init(
            id: dto.id,
            name: dto.name,
            summary: dto.summary,
            isSmart: false,
            source: .jellyfin,
            isReadOnly: dto.isFileBased(serverType: serverType),
            createdAt: nil,
            updatedAt: nil
        )
    }
}

