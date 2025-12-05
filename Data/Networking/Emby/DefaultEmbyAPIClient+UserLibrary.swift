
import Foundation

extension DefaultEmbyAPIClient {
    func fetchRecentlyPlayedImpl(limit: Int) async throws -> [JellyfinTrackDTO] {
        guard let userId = userId else {
            throw JellyfinAPIError.authenticationFailed
        }
        
        var components = URLComponents(url: buildURL(path: "Users/\(userId)/Items"), resolvingAgainstBaseURL: false)!
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
        
        let result: JellyfinBaseItemQueryResult = try await httpClient.request(request)
        
        return result.items.compactMap { item -> JellyfinTrackDTO? in
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
                playlistItemId: nil
            )
        }
    }
    
    func fetchRecentlyAddedImpl(limit: Int) async throws -> [JellyfinTrackDTO] {
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
            URLQueryItem(name: "UserId", value: userId)
        ]
        
        guard let url = components.url else {
            throw JellyfinAPIError.invalidResponse
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        addAuthHeaders(to: &request)
        
        let result: JellyfinBaseItemQueryResult = try await httpClient.request(request)
        
        return result.items.compactMap { item -> JellyfinTrackDTO? in
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
                playlistItemId: nil
            )
        }
    }
    
    func fetchLikedTracksImpl(limit: Int?) async throws -> [JellyfinTrackDTO] {
        guard let userId = userId else {
            throw JellyfinAPIError.authenticationFailed
        }
        
        var components = URLComponents(url: buildURL(path: "Users/\(userId)/Items"), resolvingAgainstBaseURL: false)!
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
        
        let result: JellyfinBaseItemQueryResult = try await httpClient.request(request)
        
        return result.items.compactMap { item -> JellyfinTrackDTO? in
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
                playlistItemId: nil
            )
        }
    }
    
    func toggleFavoriteJellyfinStyle(itemId: String, isFavorite: Bool) async throws {
        let path = "UserFavoriteItems/\(itemId)"
        var request = buildRequest(path: path, method: isFavorite ? "POST" : "DELETE")
        
        if let userId = userId {
            var components = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!
            components.queryItems = [URLQueryItem(name: "UserId", value: userId)]
            request.url = components.url
        }
        
        do {
            let _: JellyfinUserItemDataResponse = try await httpClient.request(request)
        } catch HTTPClientError.decodingError {
            // Empty response on DELETE is acceptable
        }
    }
    
    func toggleFavoriteEmbyStyle(itemId: String, isFavorite: Bool, userId: String) async throws {
        // Emby-style: POST /Users/{UserId}/Items/{ItemId}/UserData
        let path = "Users/\(userId)/Items/\(itemId)/UserData"
        var request = buildRequest(path: path, method: "POST")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        struct UserDataDto: Encodable {
            let isFavorite: Bool
            
            enum CodingKeys: String, CodingKey {
                case isFavorite = "IsFavorite"
            }
        }
        
        let userData = UserDataDto(isFavorite: isFavorite)
        let encoder = JSONEncoder()
        request.httpBody = try encoder.encode(userData)
        
        let _: JellyfinUserItemDataResponse = try await httpClient.request(request)
    }
}

