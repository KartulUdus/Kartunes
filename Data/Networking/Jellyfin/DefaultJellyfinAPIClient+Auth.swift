
import Foundation

extension DefaultJellyfinAPIClient {
    /// Resolves the final URL after following redirects (e.g., http -> https)
    /// Note: Only resolves the scheme, not the path, as Jellyfin API endpoints are at root
    func resolveFinalURL(from initialURL: URL) async throws -> URL {
        var request = URLRequest(url: initialURL)
        request.httpMethod = "HEAD" // Use HEAD to avoid downloading content
        request.timeoutInterval = 10.0
        
        let session = URLSession(configuration: .default)
        
        do {
            let (_, response) = try await session.data(for: request)
            if let httpResponse = response as? HTTPURLResponse,
               let redirectedURL = httpResponse.url {
                // Extract only the scheme and host from the redirected URL
                // Jellyfin API endpoints are at root, not under /web/ or other paths
                var components = URLComponents(url: redirectedURL, resolvingAgainstBaseURL: false)!
                // Keep only scheme, host, and port - remove any path added by redirects
                components.path = ""
                components.query = nil
                components.fragment = nil
                
                if let resolvedURL = components.url {
                    logger.debug("Resolved URL - \(initialURL.absoluteString) -> \(resolvedURL.absoluteString)")
                    return resolvedURL
                }
            }
        } catch {
            logger.warning("Could not resolve redirects for \(initialURL.absoluteString): \(error.localizedDescription)")
            // If redirect resolution fails, return the original URL
        }
        
        return initialURL
    }
    
    func authenticate(host: URL, username: String, password: String) async throws -> (finalURL: URL, userId: String, accessToken: String) {
        // First, resolve any redirects (e.g., http -> https)
        let finalURL = try await resolveFinalURL(from: host)
        
        // Build authentication URL - ensure base URL doesn't have trailing slash
        var baseURLString = finalURL.absoluteString
        if baseURLString.hasSuffix("/") {
            baseURLString = String(baseURLString.dropLast())
        }
        
        guard let normalizedBaseURL = URL(string: baseURLString) else {
            logger.error("Failed to normalize base URL: \(finalURL.absoluteString)")
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
        // Jellyfin expects PascalCase, which matches our CodingKeys
        request.httpBody = try encoder.encode(authRequest)
        
        do {
            let result: JellyfinAuthenticationResult = try await httpClient.request(request)
            
            guard let user = result.user,
                  let token = result.accessToken else {
                throw JellyfinAPIError.authenticationFailed
            }
            
            logger.info("Authentication successful - UserId: \(user.id)")
            
            // Update the API client's credentials
            updateCredentials(accessToken: token, userId: user.id)
            
            return (finalURL: finalURL, userId: user.id, accessToken: token)
        } catch {
            logger.error("Authentication failed at \(authURL.absoluteString): \(error.localizedDescription)")
            // Re-throw the error as-is (error message is already descriptive)
            throw error
        }
    }
}

