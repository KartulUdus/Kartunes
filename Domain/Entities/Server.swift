
import Foundation

struct Server: Identifiable, Codable {
    let id: UUID
    let name: String
    let baseURL: URL
    let username: String
    let userId: String
    let accessToken: String
    let serverType: MediaServerType
    
    init(id: UUID, name: String, baseURL: URL, username: String, userId: String, accessToken: String, serverType: MediaServerType = .jellyfin) {
        self.id = id
        self.name = name
        self.baseURL = baseURL
        self.username = username
        self.userId = userId
        self.accessToken = accessToken
        self.serverType = serverType
    }
}

