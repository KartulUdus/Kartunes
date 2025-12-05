
import Foundation

protocol LibraryRepository {
    func refreshLibrary() async throws
    func syncPlaylists() async throws
    func createPlaylist(name: String, summary: String?) async throws -> Playlist
    func addTracksToPlaylist(playlistId: String, trackIds: [String]) async throws
    func removeTracksFromPlaylist(playlistId: String, entryIds: [String]) async throws
    func deletePlaylist(playlistId: String) async throws
    func fetchArtists() async throws -> [Artist]
    func fetchAlbums(artistId: String?) async throws -> [Album]
    func fetchTracks(albumId: String?) async throws -> [Track]
    func fetchTracks(artistId: String?) async throws -> [Track]
    func fetchRecentlyPlayed(limit: Int) async throws -> [Track]
    func fetchRecentlyAdded(limit: Int) async throws -> [Track]
    func syncLikedTracks() async throws
    func fetchPlaylists() async throws -> [Playlist]
    func fetchPlaylistTracks(playlistId: String) async throws -> [Track]
    func fetchPlaylistEntryIds(playlistId: String) async throws -> [String: String] // Track ID -> Entry ID mapping
    func movePlaylistItem(playlistId: String, playlistItemId: String, newIndex: Int) async throws
    func search(query: String) async throws -> [Track]
    func searchAll(query: String) async throws -> SearchResults
}

