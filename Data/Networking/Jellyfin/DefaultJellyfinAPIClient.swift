
import Foundation

// MARK: - Implementation

nonisolated final class DefaultJellyfinAPIClient: JellyfinAPIClient {
    let baseURL: URL
    private var _accessToken: String?
    private var _userId: String?
    private let credentialQueue = DispatchQueue(label: "com.kartunes.jellyfin.credentials", attributes: .concurrent)
    
    var accessToken: String? {
        credentialQueue.sync { _accessToken }
    }
    
    var userId: String? {
        credentialQueue.sync { _userId }
    }
    
    let httpClient: HTTPClient
    let deviceId: String
    let serverType: MediaServerType = .jellyfin
    let logger: AppLogger
    
    init(baseURL: URL, accessToken: String? = nil, userId: String? = nil, httpClient: HTTPClient = DefaultHTTPClient(), logger: AppLogger = Log.make(.networking)) {
        self.baseURL = baseURL
        self._accessToken = accessToken
        self._userId = userId
        self.httpClient = httpClient
        self.logger = logger
        
        // Generate and store device ID (should be persisted in real app)
        let deviceIdKey = "JellyfinDeviceId"
        if let stored = UserDefaults.standard.string(forKey: deviceIdKey) {
            self.deviceId = stored
        } else {
            let newId = UUID().uuidString
            UserDefaults.standard.set(newId, forKey: deviceIdKey)
            self.deviceId = newId
        }
    }
    
    func updateCredentials(accessToken: String, userId: String) {
        credentialQueue.async(flags: .barrier) {
            self._accessToken = accessToken
            self._userId = userId
        }
    }
}

