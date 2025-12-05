
import Foundation

extension DefaultJellyfinAPIClient {
    func buildRequest(path: String, method: String = "GET") -> URLRequest {
        let url = baseURL.appendingPathComponent(path)
        var request = URLRequest(url: url)
        request.httpMethod = method
        addAuthHeaders(to: &request)
        return request
    }
    
    func addAuthHeaders(to request: inout URLRequest) {
        let authHeader = "MediaBrowser Client=\"Kartunes\", Device=\"iOS\", DeviceId=\"\(deviceId)\", Version=\"1.0.0\""
        request.setValue(authHeader, forHTTPHeaderField: "X-Emby-Authorization")
        
        if let token = accessToken {
            let tokenHeader = "MediaBrowser Token=\"\(token)\""
            request.setValue(tokenHeader, forHTTPHeaderField: "Authorization")
        }
    }
}
