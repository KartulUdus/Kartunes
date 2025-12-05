
import Foundation

/// Factory for creating appropriate API clients based on server type
enum MediaServerAPIClientFactory {
    static func createClient(
        serverType: MediaServerType,
        baseURL: URL,
        accessToken: String? = nil,
        userId: String? = nil,
        httpClient: HTTPClient = DefaultHTTPClient()
    ) -> MediaServerAPIClient {
        switch serverType {
        case .jellyfin:
            return DefaultJellyfinAPIClient(
                baseURL: baseURL,
                accessToken: accessToken,
                userId: userId,
                httpClient: httpClient
            )
        case .emby:
            return DefaultEmbyAPIClient(
                baseURL: baseURL,
                accessToken: accessToken,
                userId: userId,
                httpClient: httpClient
            )
        }
    }
    
    static func createClient(for server: Server, httpClient: HTTPClient = DefaultHTTPClient()) -> MediaServerAPIClient {
        return createClient(
            serverType: server.serverType,
            baseURL: server.baseURL,
            accessToken: server.accessToken,
            userId: server.userId,
            httpClient: httpClient
        )
    }
}

