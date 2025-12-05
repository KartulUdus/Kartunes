
import Foundation

extension DefaultEmbyAPIClient {
    func buildURL(path: String) -> URL {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
        
        // Get the existing path from baseURL
        var fullPath = components.path
        
        // Normalize: ensure path doesn't end with / (except for root paths like /emby)
        if fullPath.hasSuffix("/") && fullPath != "/" && fullPath != "/emby/" {
            fullPath = String(fullPath.dropLast())
        }
        
        // Ensure existing path ends with / if it's not empty (for appending)
        if !fullPath.isEmpty && !fullPath.hasSuffix("/") {
            fullPath += "/"
        }
        
        // Remove leading slash from the new path component if present
        let cleanPath = path.hasPrefix("/") ? String(path.dropFirst()) : path
        
        // Append the new path
        fullPath += cleanPath
        
        // Normalize: remove any duplicate slashes (e.g., /emby//Sessions -> /emby/Sessions)
        fullPath = fullPath.replacingOccurrences(of: "//", with: "/")
        
        components.path = fullPath
        
        guard let url = components.url else {
            // Fallback to appendingPathComponent if URLComponents fails
            return baseURL.appendingPathComponent(path)
        }
        
        return url
    }
    
    func buildRequest(path: String, method: String = "GET") -> URLRequest {
        let url = buildURL(path: path)
        var request = URLRequest(url: url)
        request.httpMethod = method
        addAuthHeaders(to: &request)
        return request
    }
    
    func addAuthHeaders(to request: inout URLRequest) {
        let authHeader = "MediaBrowser Client=\"Kartunes\", Device=\"iOS\", DeviceId=\"\(deviceId)\", Version=\"1.0.0\""
        request.setValue(authHeader, forHTTPHeaderField: "X-Emby-Authorization")
        
        if let token = accessToken {
            // Emby expects the token in X-Emby-Token header, not Authorization header
            request.setValue(token, forHTTPHeaderField: "X-Emby-Token")
        }
    }
    
    // MARK: - Implementation Helpers (shared logic)
    
}
