
import Foundation

// MARK: - Protocol

nonisolated protocol JellyfinAPIClient: MediaServerAPIClient {
    var accessToken: String? { get }
    var userId: String? { get }
    
    func authenticate(host: URL, username: String, password: String) async throws -> (finalURL: URL, userId: String, accessToken: String)
    func resolveFinalURL(from initialURL: URL) async throws -> URL
    func fetchMusicLibraries() async throws -> [JellyfinLibraryDTO]
    func fetchArtists() async throws -> [JellyfinArtistDTO]
    func fetchAlbums(byArtistId: String?) async throws -> [JellyfinAlbumDTO]
    func fetchTracks(byAlbumId: String?) async throws -> [JellyfinTrackDTO]
    func fetchTracks(byArtistId: String?) async throws -> [JellyfinTrackDTO]
    func fetchRecentlyPlayed(limit: Int) async throws -> [JellyfinTrackDTO]
    func fetchRecentlyAdded(limit: Int) async throws -> [JellyfinTrackDTO]
    func fetchLikedTracks(limit: Int?) async throws -> [JellyfinTrackDTO]
    func fetchInstantMix(fromItemId: String, type: InstantMixKind) async throws -> [JellyfinTrackDTO]
    func toggleFavorite(itemId: String, isFavorite: Bool) async throws
    func getMediaSourceFormat(itemId: String) async throws -> String?
    func getPlaybackInfo(itemId: String) async throws -> JellyfinPlaybackInfo?
    func buildStreamURL(forTrackId id: String, preferredCodec: String?, preferredContainer: String?) -> URL
    func buildStreamURL(forTrackId id: String) -> URL
    func buildStreamURL(forTrackId id: String, useDirectStream: Bool) async -> URL
    func buildImageURL(forItemId id: String, imageType: String, maxWidth: Int?) -> URL?
    func buildImageURL(forItemId id: String, imageType: String, maxWidth: Int?, tag: String?) -> URL?
    
    // Playlists
    func fetchPlaylists() async throws -> [JellyfinPlaylistDTO]
    func fetchPlaylistItems(playlistId: String) async throws -> [JellyfinTrackDTO]
    func createPlaylist(name: String) async throws -> JellyfinPlaylistDTO
    func addTracksToPlaylist(playlistId: String, trackIds: [String]) async throws
    func removeTracksFromPlaylist(playlistId: String, entryIds: [String]) async throws
    func deletePlaylist(playlistId: String) async throws
    func movePlaylistItem(playlistId: String, playlistItemId: String, newIndex: Int) async throws
    
    // Playback Reporting
    func reportCapabilities() async throws
    func reportPlaybackStart(itemId: String, mediaSourceId: String?, playSessionId: String, positionTicks: Int64, isPaused: Bool, playMethod: String) async throws
    func reportPlaybackProgress(itemId: String, mediaSourceId: String?, playSessionId: String, positionTicks: Int64, isPaused: Bool, eventName: String?) async throws
    func reportPlaybackStopped(itemId: String, mediaSourceId: String?, playSessionId: String, positionTicks: Int64, nextMediaType: String?) async throws
}

// MARK: - Errors

enum JellyfinAPIError: Error {
    case notImplemented
    case authenticationFailed
    case invalidResponse
    case missingUserId
    case missingAccessToken
}

