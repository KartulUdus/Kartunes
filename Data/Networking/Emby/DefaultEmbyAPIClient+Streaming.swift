
import Foundation

extension DefaultEmbyAPIClient {
    func getMediaSourceFormat(itemId: String) async throws -> String? {
        let playbackInfo = try await getPlaybackInfo(itemId: itemId)
        return playbackInfo?.mediaSources?.first?.container?.lowercased()
    }
    
    func getPlaybackInfo(itemId: String) async throws -> JellyfinPlaybackInfo? {
        var components = URLComponents(url: baseURL.appendingPathComponent("Items/\(itemId)/PlaybackInfo"), resolvingAgainstBaseURL: false)!
        
        // Emby docs specify UserId (capital U, I) as required
        if let userId = userId {
            components.queryItems = [URLQueryItem(name: "UserId", value: userId)]
        }
        
        guard let url = components.url else {
            logger.error("Failed to construct playback info URL")
            return nil
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        addAuthHeaders(to: &request)
        
        do {
            let response: JellyfinPlaybackInfo = try await httpClient.request(request)
            return response
        } catch {
            logger.warning("Failed to get playback info: \(error.localizedDescription)")
            return nil
        }
    }
    
    func buildStreamURL(forTrackId id: String) -> URL {
        // For Emby, always use direct streaming (Items/{id}/File) instead of HLS
        // HLS endpoint returns 400 errors, so direct streaming is more reliable
        let directStreamURL = buildURL(path: "Items/\(id)/File")
        var components = URLComponents(url: directStreamURL, resolvingAgainstBaseURL: false)!
        
        var queryItems: [URLQueryItem] = []
        if let token = accessToken, !token.isEmpty {
            queryItems.append(URLQueryItem(name: "api_key", value: token))
        }
        
        components.queryItems = queryItems.isEmpty ? nil : queryItems
        
        return components.url ?? directStreamURL
    }
    
    func buildStreamURL(forTrackId id: String, useDirectStream: Bool) async -> URL {
        if !useDirectStream {
            return buildStreamURL(forTrackId: id, preferredCodec: nil, preferredContainer: nil)
        }
        
        // For Emby, always try direct streaming first (even if PlaybackInfo says it's not supported)
        // Emby's HLS endpoint often returns 400, so direct streaming is more reliable
        let directStreamURL = buildURL(path: "Items/\(id)/File")
        var components = URLComponents(url: directStreamURL, resolvingAgainstBaseURL: false)!
        
        var queryItems: [URLQueryItem] = []
        if let token = accessToken, !token.isEmpty {
            // Emby expects api_key (lowercase with underscore) for query parameters
            queryItems.append(URLQueryItem(name: "api_key", value: token))
        }
        
        components.queryItems = queryItems.isEmpty ? nil : queryItems
        
        if let streamURL = components.url {
            logger.debug("Using direct stream for \(id) - URL: \(streamURL.absoluteString)")
            return streamURL
        }
        
        // Fallback to HLS only if direct streaming URL construction fails
        logger.warning("Direct stream URL construction failed for \(id), falling back to HLS")
        return buildStreamURL(forTrackId: id, preferredCodec: nil, preferredContainer: nil)
    }
    
    func buildStreamURL(forTrackId id: String, preferredCodec: String?, preferredContainer: String?) -> URL {
        let audioCodec = preferredCodec ?? "aac"
        var components = URLComponents(url: buildURL(path: "Audio/\(id)/main.m3u8"), resolvingAgainstBaseURL: false)!
        
        var queryItems: [URLQueryItem] = []
        
        if let token = accessToken, !token.isEmpty {
            // Emby expects api_key (lowercase with underscore) for query parameters
            queryItems.append(URLQueryItem(name: "api_key", value: token))
        }
        
        if let userId = userId {
            queryItems.append(URLQueryItem(name: "UserId", value: userId))
        }
        
        queryItems.append(URLQueryItem(name: "audioCodec", value: audioCodec))
        queryItems.append(URLQueryItem(name: "audioSampleRate", value: "44100"))
        queryItems.append(URLQueryItem(name: "maxAudioBitDepth", value: "16"))
        queryItems.append(URLQueryItem(name: "audioBitRate", value: "320000"))
        queryItems.append(URLQueryItem(name: "deviceId", value: deviceId))
        
        components.queryItems = queryItems.isEmpty ? nil : queryItems
        
        guard let streamURL = components.url else {
            return buildURL(path: "Audio/\(id)/stream")
        }
        
        return streamURL
    }
    
    func buildImageURL(forItemId id: String, imageType: String, maxWidth: Int?) -> URL? {
        return buildImageURL(forItemId: id, imageType: imageType, maxWidth: maxWidth, tag: nil)
    }
    
    /// Returns a list of image types to try for albums when ImageTags is not available
    /// For Emby, we try multiple types since ImageTags may not be returned in list queries
    func getImageTypesToTry() -> [String] {
        return ["Primary", "Backdrop", "Logo", "Thumb", "Disc", "Art"]
    }
    
    func buildImageURL(forItemId id: String, imageType: String, maxWidth: Int?, tag: String?) -> URL? {
        let imagePath = "Items/\(id)/Images/\(imageType)"
        var components = URLComponents(url: buildURL(path: imagePath), resolvingAgainstBaseURL: false)!
        
        var queryItems: [URLQueryItem] = []
        
        // Emby web UI uses both maxWidth and maxHeight (matching the web UI format)
        if let maxWidth = maxWidth {
            queryItems.append(URLQueryItem(name: "maxWidth", value: "\(maxWidth)"))
            queryItems.append(URLQueryItem(name: "maxHeight", value: "\(maxWidth)")) // Use same value for both
        }
        
        // Add tag parameter if provided (helps with caching and ensures correct image)
        if let tag = tag, !tag.isEmpty {
            queryItems.append(URLQueryItem(name: "tag", value: tag))
        }
        
        // Emby web UI uses quality=90 parameter
        queryItems.append(URLQueryItem(name: "quality", value: "90"))
        
        // Use api_key for authentication (Emby expects this in query params)
        if let token = accessToken {
            queryItems.append(URLQueryItem(name: "api_key", value: token))
        }
        
        components.queryItems = queryItems.isEmpty ? nil : queryItems
        
        return components.url
    }
    
    // MARK: - Playlists
    
}
