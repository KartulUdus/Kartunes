
import Foundation

extension DefaultJellyfinAPIClient {
    func fetchPlaylists() async throws -> [JellyfinPlaylistDTO] {
        guard let userId = userId else {
            throw JellyfinAPIError.missingUserId
        }
        
        var components = URLComponents(url: baseURL.appendingPathComponent("Users/\(userId)/Items"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "IncludeItemTypes", value: "Playlist"),
            URLQueryItem(name: "Recursive", value: "true"),
            URLQueryItem(name: "Fields", value: "Overview,IsFolder,Path,LocationType,DateCreated,DateModified"),
            URLQueryItem(name: "SortBy", value: "SortName")
        ]
        
        guard let url = components.url else {
            throw JellyfinAPIError.invalidResponse
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        addAuthHeaders(to: &request)
        
        do {
            let result: JellyfinBaseItemQueryResult = try await httpClient.request(request)
            
            let playlists = result.items.compactMap { item -> JellyfinPlaylistDTO? in
                guard item.type == "Playlist" else { return nil }
                
                return JellyfinPlaylistDTO(
                    id: item.id,
                    name: item.name,
                    summary: item.overview,
                    isFolder: item.isFolder,
                    path: item.path,
                    locationType: item.locationType,
                    ownerUserId: userId
                )
            }
            
            logger.info("Fetched \(playlists.count) playlists")
            return playlists
        } catch {
            logger.error("Error fetching playlists: \(error.localizedDescription)")
            // If there's an error, return empty array instead of throwing
            // This prevents one bad playlist from breaking the entire list
            if let httpError = error as? HTTPClientError,
               case .httpError(let statusCode) = httpError,
               statusCode == 400 {
                logger.warning("Got 400 error fetching playlists - possibly due to empty/corrupted playlist, returning empty list")
                return []
            }
            throw error
        }
    }
    
    func fetchPlaylistItems(playlistId: String) async throws -> [JellyfinTrackDTO] {
        guard let userId = userId else {
            throw JellyfinAPIError.missingUserId
        }
        
        var components = URLComponents(url: baseURL.appendingPathComponent("Playlists/\(playlistId)/Items"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "userId", value: userId),
            URLQueryItem(name: "Fields", value: "Name,RunTimeTicks,AlbumId,Album,Artists,Genres,IndexNumber,DiscNumber,ImageTags,UserData,DateCreated,PlayCount,Container,PlaylistItemId")
        ]
        
        guard let url = components.url else {
            throw JellyfinAPIError.invalidResponse
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        addAuthHeaders(to: &request)
        
        do {
            let result: JellyfinBaseItemQueryResult = try await httpClient.request(request)
            
            let tracks = result.items.compactMap { item -> JellyfinTrackDTO? in
                guard item.type == "Audio" else { return nil }
                
                return JellyfinTrackDTO(
                    id: item.id,
                    name: item.name,
                    albumId: item.albumId,
                    album: item.album,
                    artists: item.artists,
                    genres: item.genres,
                    runTimeTicks: item.runTimeTicks,
                    indexNumber: item.indexNumber,
                    discNumber: item.discNumber,
                    dateAdded: item.dateAdded,
                    playCount: item.playCount,
                    container: item.container,
                    userData: item.userData,
                    playlistItemId: item.playlistItemId
                )
            }
            
            logger.info("Fetched \(tracks.count) tracks from playlist \(playlistId)")
            return tracks
        } catch {
            logger.error("Error fetching playlist items: \(error.localizedDescription)")
            throw error
        }
    }
    
    func createPlaylist(name: String) async throws -> JellyfinPlaylistDTO {
        guard let userId = userId else {
            throw JellyfinAPIError.missingUserId
        }
        
        // According to OpenAPI spec, use request body (query params are deprecated)
        let url = baseURL.appendingPathComponent("Playlists")
        
        struct CreatePlaylistDto: Encodable {
            let name: String
            let userId: String?
            let ids: [String]?
            
            enum CodingKeys: String, CodingKey {
                case name = "Name"
                case userId = "UserId"
                case ids = "Ids"
            }
        }
        
        let createDto = CreatePlaylistDto(name: name, userId: userId, ids: nil)
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        addAuthHeaders(to: &request)
        
        // Encode the request body
        let encoder = JSONEncoder()
        request.httpBody = try encoder.encode(createDto)
        
        do {
            // According to Jellyfin OpenAPI spec, POST /Playlists returns PlaylistCreationResult
            // which only contains an "Id" field
            struct PlaylistCreationResult: Decodable {
                let id: String
                
                enum CodingKeys: String, CodingKey {
                    case id = "Id"
                }
            }
            
            // Decode the response to get the playlist ID
            let result: PlaylistCreationResult = try await httpClient.request(request)
            let playlistId = result.id
            
            logger.info("Created playlist '\(name)' with ID \(playlistId)")
            
            // Now fetch the full playlist details
            // Wait a moment for the server to process
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
            
            // Fetch all playlists and find the one we just created
            do {
                let playlists = try await fetchPlaylists()
                if let createdPlaylist = playlists.first(where: { $0.id == playlistId }) {
                    return createdPlaylist
                }
            } catch {
                logger.warning("Could not fetch playlists after creation: \(error.localizedDescription)")
                // Continue with fallback
            }
            
            // If we can't find it in the list, create a minimal DTO
            // This should be rare, but provides a fallback
            logger.warning("Created playlist but couldn't fetch details, using minimal DTO")
            return JellyfinPlaylistDTO(
                id: playlistId,
                name: name,
                summary: nil,
                isFolder: nil,
                path: nil,
                locationType: "Virtual",
                ownerUserId: userId
            )
        } catch {
            logger.error("Error creating playlist: \(error.localizedDescription)")
            throw error
        }
    }
    
    func addTracksToPlaylist(playlistId: String, trackIds: [String]) async throws {
        guard let userId = userId else {
            throw JellyfinAPIError.missingUserId
        }
        
        // Join track IDs with commas
        let idsString = trackIds.joined(separator: ",")
        
        var components = URLComponents(url: baseURL.appendingPathComponent("Playlists/\(playlistId)/Items"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "Ids", value: idsString),
            URLQueryItem(name: "UserId", value: userId)
        ]
        
        guard let url = components.url else {
            throw JellyfinAPIError.invalidResponse
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        addAuthHeaders(to: &request)
        
        do {
            // Response is typically empty or a success status
            let _: EmptyResponse? = try await httpClient.request(request)
            logger.info("Added \(trackIds.count) tracks to playlist \(playlistId)")
        } catch {
            logger.error("Error adding tracks to playlist: \(error.localizedDescription)")
            throw error
        }
    }
    
    func removeTracksFromPlaylist(playlistId: String, entryIds: [String]) async throws {
        guard let userId = userId else {
            throw JellyfinAPIError.missingUserId
        }
        
        // Join entry IDs with commas
        let entryIdsString = entryIds.joined(separator: ",")
        
        var components = URLComponents(url: baseURL.appendingPathComponent("Playlists/\(playlistId)/Items"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "EntryIds", value: entryIdsString),
            URLQueryItem(name: "UserId", value: userId)
        ]
        
        guard let url = components.url else {
            throw JellyfinAPIError.invalidResponse
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        addAuthHeaders(to: &request)
        
        do {
            // Response is typically empty or a success status
            let _: EmptyResponse? = try await httpClient.request(request)
            logger.info("Removed \(entryIds.count) tracks from playlist \(playlistId)")
        } catch {
            logger.error("Error removing tracks from playlist: \(error.localizedDescription)")
            throw error
        }
    }
    
    func deletePlaylist(playlistId: String) async throws {
        let url = baseURL.appendingPathComponent("Playlists/\(playlistId)")
        
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        addAuthHeaders(to: &request)
        
        do {
            // Response is typically empty or a success status
            let _: EmptyResponse? = try await httpClient.request(request)
            logger.info("Deleted playlist \(playlistId)")
        } catch {
            logger.error("Error deleting playlist: \(error.localizedDescription)")
            throw error
        }
    }
    
    func movePlaylistItem(playlistId: String, playlistItemId: String, newIndex: Int) async throws {
        let url = baseURL.appendingPathComponent("Playlists/\(playlistId)/Items/\(playlistItemId)/Move/\(newIndex)")
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        addAuthHeaders(to: &request)
        
        do {
            // No body required, just POST to the endpoint
            let _: EmptyResponse = try await httpClient.request(request)
            logger.info("Moved playlist item \(playlistItemId) to index \(newIndex) in playlist \(playlistId)")
        } catch {
            logger.error("Error moving playlist item: \(error.localizedDescription)")
            throw error
        }
    }
}
