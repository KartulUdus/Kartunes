
import Foundation

extension DefaultJellyfinAPIClient {
    func fetchRecentlyPlayed(limit: Int = 50) async throws -> [JellyfinTrackDTO] {
        guard let userId = userId else {
            throw JellyfinAPIError.authenticationFailed
        }
        
        var components = URLComponents(url: baseURL.appendingPathComponent("Users/\(userId)/Items"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "IncludeItemTypes", value: "Audio"),
            URLQueryItem(name: "SortBy", value: "DatePlayed"),
            URLQueryItem(name: "SortOrder", value: "Descending"),
            URLQueryItem(name: "Filters", value: "IsPlayed"),
            URLQueryItem(name: "Recursive", value: "true"),
            URLQueryItem(name: "Limit", value: "\(limit)"),
            URLQueryItem(name: "EnableUserData", value: "true"),
            URLQueryItem(name: "Fields", value: "Name,RunTimeTicks,AlbumId,Album,Artists,Genres,IndexNumber,DiscNumber,ParentId,ImageTags,UserData,DateCreated,PlayCount,Container")
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
                guard item.type == "Audio" else {
                    return nil
                }
                
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
                    playlistItemId: nil
                )
            }
            
            logger.info("Fetched \(tracks.count) recently played tracks")
            return tracks
        } catch {
            throw error
        }
    }
    
    func fetchRecentlyAdded(limit: Int = 500) async throws -> [JellyfinTrackDTO] {
        guard let userId = userId else {
            throw JellyfinAPIError.authenticationFailed
        }
        
        var components = URLComponents(url: baseURL.appendingPathComponent("Items"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "IncludeItemTypes", value: "Audio"),
            URLQueryItem(name: "SortBy", value: "DateCreated"),
            URLQueryItem(name: "SortOrder", value: "Descending"),
            URLQueryItem(name: "Recursive", value: "true"),
            URLQueryItem(name: "Limit", value: "\(limit)"),
            URLQueryItem(name: "EnableUserData", value: "true"),
            URLQueryItem(name: "Fields", value: "Name,RunTimeTicks,AlbumId,Album,Artists,Genres,IndexNumber,DiscNumber,ParentId,ImageTags,UserData,DateCreated,PlayCount,Container"),
            URLQueryItem(name: "userId", value: userId)
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
                guard item.type == "Audio" else {
                    return nil
                }
                
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
                    playlistItemId: nil
                )
            }
            
            logger.info("Fetched \(tracks.count) recently added tracks")
            return tracks
        } catch {
            throw error
        }
    }
    
    func fetchLikedTracks(limit: Int? = nil) async throws -> [JellyfinTrackDTO] {
        guard let userId = userId else {
            throw JellyfinAPIError.authenticationFailed
        }
        
        var components = URLComponents(url: baseURL.appendingPathComponent("Users/\(userId)/Items"), resolvingAgainstBaseURL: false)!
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "IncludeItemTypes", value: "Audio"),
            URLQueryItem(name: "Filters", value: "IsFavorite"),
            URLQueryItem(name: "Recursive", value: "true"),
            URLQueryItem(name: "EnableUserData", value: "true"),
            URLQueryItem(name: "Fields", value: "Name,RunTimeTicks,AlbumId,Album,Artists,Genres,IndexNumber,DiscNumber,ParentId,ImageTags,UserData,DateCreated,PlayCount,Container")
        ]
        
        if let limit = limit {
            queryItems.append(URLQueryItem(name: "Limit", value: "\(limit)"))
        }
        
        components.queryItems = queryItems
        
        guard let url = components.url else {
            throw JellyfinAPIError.invalidResponse
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        addAuthHeaders(to: &request)
        
        do {
            let result: JellyfinBaseItemQueryResult = try await httpClient.request(request)
            
            let tracks = result.items.compactMap { item -> JellyfinTrackDTO? in
                guard item.type == "Audio" else {
                    return nil
                }
                
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
                    playlistItemId: nil
                )
            }
            
            logger.info("Fetched \(tracks.count) liked tracks")
            return tracks
        } catch {
            throw error
        }
    }
    
    func toggleFavorite(itemId: String, isFavorite: Bool) async throws {
        let path = "UserFavoriteItems/\(itemId)"
        var request = buildRequest(path: path, method: isFavorite ? "POST" : "DELETE")
        
        if let userId = userId {
            var components = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!
            components.queryItems = [URLQueryItem(name: "userId", value: userId)]
            request.url = components.url
        }
        
        // Make the request - response is UserItemDataDto but we don't need to decode it
        // For DELETE, response might be empty, so we handle it gracefully
        do {
            let _: JellyfinUserItemDataResponse = try await httpClient.request(request)
        } catch HTTPClientError.decodingError {
            // Empty response on DELETE is acceptable - HTTP status was 200
            // This means the operation succeeded
        }
    }
}

