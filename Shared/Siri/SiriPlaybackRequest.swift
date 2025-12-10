
import Foundation

/// Represents a playback request from Siri
enum SiriPlaybackRequestType: Codable {
    case artist(id: String)
    case album(id: String)
    case track(id: String)
    case playlist(id: String)
}

struct SiriPlaybackRequest: Codable {
    let type: SiriPlaybackRequestType
    let shuffle: Bool
}

/// Manages communication between the Intents Extension and the main app via App Group
final class SiriPlaybackRequestManager {
    private static let appGroupIdentifier = "group.com.kartul.kartunes"
    private static let requestKey = "pendingSiriPlaybackRequest"
    
    private let userDefaults: UserDefaults?
    
    init() {
        self.userDefaults = UserDefaults(suiteName: Self.appGroupIdentifier)
    }
    
    /// Save a playback request from the extension
    func saveRequest(_ request: SiriPlaybackRequest) {
        guard let userDefaults = userDefaults else {
            NSLog("SiriPlaybackRequestManager: Failed to access App Group UserDefaults")
            return
        }
        
        if let encoded = try? JSONEncoder().encode(request) {
            userDefaults.set(encoded, forKey: Self.requestKey)
            userDefaults.synchronize()
        }
    }
    
    /// Retrieve and consume a pending playback request in the app
    func consumeRequest() -> SiriPlaybackRequest? {
        guard let userDefaults = userDefaults else {
            return nil
        }
        
        guard let data = userDefaults.data(forKey: Self.requestKey) else {
            return nil
        }
        
        // Clear the request after reading
        userDefaults.removeObject(forKey: Self.requestKey)
        userDefaults.synchronize()
        
        return try? JSONDecoder().decode(SiriPlaybackRequest.self, from: data)
    }
}

