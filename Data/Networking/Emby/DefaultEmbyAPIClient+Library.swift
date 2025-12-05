
import Foundation

extension DefaultEmbyAPIClient {
    func fetchMusicLibraries() async throws -> [JellyfinLibraryDTO] {
        // Emby uses /Library/VirtualFolders/Query instead of /Library/VirtualFolders
        let request = buildRequest(path: "Library/VirtualFolders/Query", method: "GET")
        
        do {
            let folders: [JellyfinVirtualFolderInfo] = try await httpClient.request(request)
            return folders.map { folder in
                JellyfinLibraryDTO(id: folder.itemId ?? folder.name, name: folder.name)
            }
        } catch {
            // Fallback to non-Query endpoint if Query doesn't work
            logger.debug("Query endpoint failed, trying fallback")
            let fallbackRequest = buildRequest(path: "Library/VirtualFolders", method: "GET")
            let folders: [JellyfinVirtualFolderInfo] = try await httpClient.request(fallbackRequest)
            return folders.map { folder in
                JellyfinLibraryDTO(id: folder.itemId ?? folder.name, name: folder.name)
            }
        }
    }
    
    // MARK: - Delegate to Jellyfin implementation for most methods
    
    // Most methods are identical, so we'll reuse the Jellyfin implementation
    // by creating a shared helper or by implementing them similarly
    
    func fetchArtists() async throws -> [JellyfinArtistDTO] {
        return try await fetchArtistsImpl()
    }
    
    func fetchAlbums(byArtistId: String?) async throws -> [JellyfinAlbumDTO] {
        return try await fetchAlbumsImpl(byArtistId: byArtistId)
    }
    
    func fetchTracks(byAlbumId: String?) async throws -> [JellyfinTrackDTO] {
        return try await fetchTracksImpl(byAlbumId: byAlbumId, byArtistId: nil as String?)
    }
    
    func fetchTracks(byArtistId: String?) async throws -> [JellyfinTrackDTO] {
        return try await fetchTracksImpl(byAlbumId: nil as String?, byArtistId: byArtistId)
    }
    
    func fetchRecentlyPlayed(limit: Int = 50) async throws -> [JellyfinTrackDTO] {
        return try await fetchRecentlyPlayedImpl(limit: limit)
    }
    
    func fetchRecentlyAdded(limit: Int = 500) async throws -> [JellyfinTrackDTO] {
        return try await fetchRecentlyAddedImpl(limit: limit)
    }
    
    func fetchLikedTracks(limit: Int? = nil) async throws -> [JellyfinTrackDTO] {
        return try await fetchLikedTracksImpl(limit: limit)
    }
    
    func fetchInstantMix(fromItemId: String, type: InstantMixKind) async throws -> [JellyfinTrackDTO] {
        return try await fetchInstantMixImpl(fromItemId: fromItemId, type: type)
    }
    
    func toggleFavorite(itemId: String, isFavorite: Bool) async throws {
        // Emby may prefer /Users/{UserId}/Items/{ItemId}/UserData
        // Try Jellyfin-style first, fallback to Emby-style if needed
        if let userId = userId {
            do {
                return try await toggleFavoriteEmbyStyle(itemId: itemId, isFavorite: isFavorite, userId: userId)
            } catch {
                // Fallback to Jellyfin-style endpoint
                logger.debug("Emby-style favorite toggle failed, trying Jellyfin-style")
                return try await toggleFavoriteJellyfinStyle(itemId: itemId, isFavorite: isFavorite)
            }
        } else {
            return try await toggleFavoriteJellyfinStyle(itemId: itemId, isFavorite: isFavorite)
        }
    }
}
