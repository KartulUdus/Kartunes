
import Foundation

// MARK: - Implementation

final class DefaultEmbyAPIClient: EmbyAPIClient {
    let baseURL: URL
    private(set) var accessToken: String?
    private(set) var userId: String?
    let httpClient: HTTPClient
    let deviceId: String
    let serverType: MediaServerType = .emby
    let logger: AppLogger
    
    init(baseURL: URL, accessToken: String? = nil, userId: String? = nil, httpClient: HTTPClient = DefaultHTTPClient(), logger: AppLogger = Log.make(.networking)) {
        self.baseURL = baseURL
        self.accessToken = accessToken
        self.userId = userId
        self.httpClient = httpClient
        self.logger = logger
        
        // Generate and store device ID (should be persisted in real app)
        let deviceIdKey = "EmbyDeviceId"
        if let stored = UserDefaults.standard.string(forKey: deviceIdKey) {
            self.deviceId = stored
        } else {
            let newId = UUID().uuidString
            UserDefaults.standard.set(newId, forKey: deviceIdKey)
            self.deviceId = newId
        }
    }
    
    func updateCredentials(accessToken: String, userId: String) {
        self.accessToken = accessToken
        self.userId = userId
    }
}

