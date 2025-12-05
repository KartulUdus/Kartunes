
import Foundation

extension DefaultJellyfinAPIClient {
    func fetchInstantMix(fromItemId: String, type: InstantMixKind) async throws -> [JellyfinTrackDTO] {
        let path: String
        switch type {
        case .album:
            path = "Albums/\(fromItemId)/InstantMix"
        case .artist:
            path = "Artists/\(fromItemId)/InstantMix"
        case .song:
            path = "Items/\(fromItemId)/InstantMix"
        case .genre:
            path = "Items/\(fromItemId)/InstantMix" // Genres use Items endpoint
        }
        
        var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "Limit", value: "50")
        ]
        
        if let userId = userId {
            components.queryItems?.append(URLQueryItem(name: "userId", value: userId))
            components.queryItems?.append(URLQueryItem(name: "EnableUserData", value: "true"))
        }
        
        var request = URLRequest(url: components.url!)
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
}
