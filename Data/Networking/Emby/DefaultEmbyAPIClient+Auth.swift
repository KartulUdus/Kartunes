
import Foundation

extension DefaultEmbyAPIClient {
    func resolveFinalURL(from initialURL: URL) async throws -> URL {
        var request = URLRequest(url: initialURL)
        request.httpMethod = "HEAD"
        request.timeoutInterval = 10.0
        
        let session = URLSession(configuration: .default)
        
        var resolvedURL = initialURL
        
        do {
            let (_, response) = try await session.data(for: request)
            if let httpResponse = response as? HTTPURLResponse,
               let redirectedURL = httpResponse.url {
                // For Emby, preserve the path (e.g., /emby)
                // Only adjust scheme/host/port if redirected
                var components = URLComponents(url: redirectedURL, resolvingAgainstBaseURL: false)!
                // Keep the path - don't strip it like we do for Jellyfin
                components.query = nil
                components.fragment = nil
                
                if let url = components.url {
                    resolvedURL = url
                    logger.debug("Resolved URL - \(initialURL.absoluteString) -> \(resolvedURL.absoluteString)")
                }
            }
        } catch {
            logger.warning("Could not resolve redirects for \(initialURL.absoluteString): \(error.localizedDescription)")
        }
        
        // Ensure /emby is in the path if not present
        // Remove common web paths like /web/index.html and ensure /emby is present
        var components = URLComponents(url: resolvedURL, resolvingAgainstBaseURL: false)!
        var path = components.path
        
        // Remove common web UI paths
        if path.contains("/web/") {
            path = path.replacingOccurrences(of: "/web/.*", with: "", options: .regularExpression)
        }
        if path.contains("/index.html") {
            path = path.replacingOccurrences(of: "/index.html", with: "")
        }
        
        // Normalize path - remove trailing slashes
        path = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        
        // Check if /emby is already in the path (avoid duplicates)
        // Check for /emby/ or /emby at the start, or ending with /emby
        let hasEmby = path.hasPrefix("emby/") || path == "emby" || path.hasSuffix("/emby") || path.contains("/emby/")
        
        if !hasEmby {
            // Add /emby if not present
            if path.isEmpty {
                path = "/emby"
            } else {
                path = "/emby/" + path
            }
        } else {
            // Ensure path starts with /emby (normalize if it's in the middle or end)
            if !path.hasPrefix("emby") {
                // Extract just the /emby part and what comes after it
                if let embyRange = path.range(of: "/emby") {
                    let afterEmby = String(path[embyRange.upperBound...])
                    path = "/emby" + (afterEmby.hasPrefix("/") ? afterEmby : "/" + afterEmby)
                } else if path.hasSuffix("/emby") {
                    path = "/emby"
                }
            } else if !path.hasPrefix("/emby") {
                path = "/" + path
            }
        }
        
        components.path = path
        components.query = nil
        components.fragment = nil
        
        if let finalURL = components.url {
            logger.debug("Final URL with /emby path: \(finalURL.absoluteString)")
            return finalURL
        }
        
        return resolvedURL
    }
    
    func authenticate(host: URL, username: String, password: String) async throws -> (finalURL: URL, userId: String, accessToken: String) {
        // For Emby, preserve the path (don't strip it)
        var finalURL = try await resolveFinalURL(from: host)
        
        // Try authentication - if it fails with 404, try adding /emby to the path
        do {
            return try await attemptAuthentication(baseURL: finalURL, username: username, password: password)
        } catch {
            // Check if it's a 404 error and /emby is not in the path
            if case HTTPClientError.httpError(404) = error {
                var components = URLComponents(url: finalURL, resolvingAgainstBaseURL: false)!
                let path = components.path
                
                // Only try /emby fallback if it's not already in the path
                if !path.contains("/emby") {
                    logger.warning("Authentication failed with 404, trying with /emby path")
                    
                    // Ensure /emby is in the path
                    var newPath = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                    // Remove any web UI paths
                    if newPath.contains("web") || newPath.contains("index.html") {
                        newPath = ""
                    }
                    if newPath.isEmpty {
                        newPath = "/emby"
                    } else if !newPath.hasPrefix("/emby") {
                        newPath = "/emby" + (newPath.hasPrefix("/") ? newPath : "/" + newPath)
                    }
                    
                    components.path = newPath
                    components.query = nil
                    components.fragment = nil
                    
                    if let newBaseURL = components.url {
                        finalURL = newBaseURL
                        logger.debug("Retrying authentication with URL: \(finalURL.absoluteString)")
                        return try await attemptAuthentication(baseURL: finalURL, username: username, password: password)
                    }
                }
            }
            
            // Re-throw the original error if fallback didn't work or wasn't applicable
            logger.error("Authentication failed at \(finalURL.absoluteString): \(error.localizedDescription)")
            throw error
        }
    }
    
    private func attemptAuthentication(baseURL: URL, username: String, password: String) async throws -> (finalURL: URL, userId: String, accessToken: String) {
        // Build authentication URL - preserve any path (e.g., /emby)
        var baseURLString = baseURL.absoluteString
        // Remove trailing slash if present, but keep path
        if baseURLString.hasSuffix("/") {
            baseURLString = String(baseURLString.dropLast())
        }
        
        guard let normalizedBaseURL = URL(string: baseURLString) else {
            logger.error("Failed to normalize base URL: \(baseURL.absoluteString)")
            throw JellyfinAPIError.invalidResponse
        }
        
        // Use appendingPathComponent which handles path construction correctly
        let authURL = normalizedBaseURL.appendingPathComponent("Users/AuthenticateByName")
        
        logger.debug("Authenticating at \(authURL.absoluteString)")
        
        var request = URLRequest(url: authURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("MediaBrowser Client=\"Kartunes\", Device=\"iOS\", DeviceId=\"\(deviceId)\", Version=\"1.0.0\"", forHTTPHeaderField: "X-Emby-Authorization")
        
        let authRequest = JellyfinAuthenticateRequest(username: username, password: password)
        let encoder = JSONEncoder()
        request.httpBody = try encoder.encode(authRequest)
        
        let result: JellyfinAuthenticationResult = try await httpClient.request(request)
        
        guard let user = result.user,
              let token = result.accessToken else {
            throw JellyfinAPIError.authenticationFailed
        }
        
        logger.info("Authentication successful - UserId: \(user.id)")
        
        // Update the API client's credentials
        updateCredentials(accessToken: token, userId: user.id)
        
        return (finalURL: baseURL, userId: user.id, accessToken: token)
    }
}
