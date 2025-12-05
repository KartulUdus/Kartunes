
import Foundation

extension DefaultJellyfinAPIClient {
    func getMediaSourceFormat(itemId: String) async throws -> String? {
        let playbackInfo = try await getPlaybackInfo(itemId: itemId)
        return playbackInfo?.mediaSources?.first?.container?.lowercased()
    }
    
    func getPlaybackInfo(itemId: String) async throws -> JellyfinPlaybackInfo? {
        // Fetch playback info to get the media source information
        var components = URLComponents(url: baseURL.appendingPathComponent("Items/\(itemId)/PlaybackInfo"), resolvingAgainstBaseURL: false)!
        
        if let userId = userId {
            components.queryItems = [URLQueryItem(name: "userId", value: userId)]
        }
        
        var request = URLRequest(url: components.url!)
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
        return buildStreamURL(forTrackId: id, preferredCodec: nil, preferredContainer: nil)
    }
    
    /// Builds a stream URL, checking PlaybackInfo to use direct streaming when available
    /// This follows FinAmp's approach: use direct streaming when possible, fall back to HLS transcoding
    func buildStreamURL(forTrackId id: String, useDirectStream: Bool) async -> URL {
        // If useDirectStream is false, always use transcoding
        if !useDirectStream {
            return buildStreamURL(forTrackId: id, preferredCodec: nil, preferredContainer: nil)
        }
        
        // Check PlaybackInfo to see if direct streaming is available
        if let playbackInfo = try? await getPlaybackInfo(itemId: id),
           let mediaSource = playbackInfo.mediaSources?.first,
           (mediaSource.supportsDirectStream == true || mediaSource.supportsDirectPlay == true) {
            // Use direct streaming endpoint: Items/{id}/File (based on FinAmp)
            var components = URLComponents(url: baseURL.appendingPathComponent("Items/\(id)/File"), resolvingAgainstBaseURL: false)!
            
            var queryItems: [URLQueryItem] = []
            
            // Use ApiKey as query parameter for authentication (same as FinAmp)
            if let token = accessToken, !token.isEmpty {
                queryItems.append(URLQueryItem(name: "ApiKey", value: token))
            }
            
            components.queryItems = queryItems.isEmpty ? nil : queryItems
            
            if let streamURL = components.url {
                logger.debug("Using direct stream for \(id)")
                return streamURL
            }
        }
        
        // Fall back to HLS transcoding if direct streaming isn't available
        logger.debug("Using HLS transcoding for \(id)")
        return buildStreamURL(forTrackId: id, preferredCodec: nil, preferredContainer: nil)
    }
    
    func buildStreamURL(forTrackId id: String, preferredCodec: String?, preferredContainer: String?) -> URL {
        // Determine codec and container
        let audioCodec = preferredCodec ?? "aac"
        
        // Use HLS (HTTP Live Streaming) endpoint for transcoding - iOS AVPlayer handles HLS natively
        // HLS is more reliable than direct streaming for transcoded content
        // Format: /Audio/{id}/main.m3u8 (based on FinAmp)
        var components = URLComponents(url: baseURL.appendingPathComponent("Audio/\(id)/main.m3u8"), resolvingAgainstBaseURL: false)!
        
        var queryItems: [URLQueryItem] = []
        
        // For HLS, use ApiKey as query parameter instead of headers (based on finamp approach)
        // This is more reliable because HLS segments are fetched directly by AVPlayer
        // and query parameters are automatically included in segment URLs
        if let token = accessToken, !token.isEmpty {
            queryItems.append(URLQueryItem(name: "ApiKey", value: token))
        }
        
        // Add user ID if available (required for some Jellyfin setups)
        if let userId = userId {
            queryItems.append(URLQueryItem(name: "userId", value: userId))
        }
        
        // Specify audio codec for transcoding
        queryItems.append(URLQueryItem(name: "audioCodec", value: audioCodec))
        
        // Audio sample rate (44.1kHz is standard)
        queryItems.append(URLQueryItem(name: "audioSampleRate", value: "44100"))
        
        // Max audio bit depth (16-bit is standard)
        queryItems.append(URLQueryItem(name: "maxAudioBitDepth", value: "16"))
        
        // Audio bitrate for transcoding (320kbps is high quality)
        queryItems.append(URLQueryItem(name: "audioBitRate", value: "320000"))
        
        // Device ID for tracking (used to stop encoding processes when needed)
        queryItems.append(URLQueryItem(name: "deviceId", value: deviceId))
        
        // Strategy (based on finamp approach):
        // - Use HLS (main.m3u8) for transcoding - iOS AVPlayer handles this natively
        // - Use ApiKey query parameter for authentication (more reliable for HLS)
        // - If FLAC detected: Request ALAC codec (lossless, iOS native)
        // - Otherwise: Request AAC codec (lossy, widely compatible)
        // - HLS ensures proper streaming and format compatibility
        
        components.queryItems = queryItems.isEmpty ? nil : queryItems
        
        guard let streamURL = components.url else {
            // Fallback to regular stream endpoint
            return baseURL.appendingPathComponent("Audio/\(id)/stream")
        }
        
        // For HLS, return the URL directly without custom scheme
        // AVPlayer handles HLS natively and will use the ApiKey query parameter
        // for authentication on all requests (playlist and segments)
        return streamURL
    }
    
    /// Converts a Jellyfin URL to use custom scheme for authenticated streaming
    private func createAuthenticatedStreamURL(from url: URL, accessToken: String, userId: String?) -> URL {
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        
        // Use custom scheme
        let isSecure = components.scheme == "https"
        components.scheme = "jellyfin"
        
        // Embed host in path for resource loader to extract
        let host = components.host ?? ""
        components.host = isSecure ? "secure" : "insecure"
        components.path = "/\(host)\(components.path)"
        
        return components.url ?? url
    }
    
    func buildImageURL(forItemId id: String, imageType: String, maxWidth: Int?) -> URL? {
        return buildImageURL(forItemId: id, imageType: imageType, maxWidth: maxWidth, tag: nil)
    }
    
    func buildImageURL(forItemId id: String, imageType: String, maxWidth: Int?, tag: String?) -> URL? {
        // Ensure baseURL doesn't have trailing slash before appending
        var baseURLString = baseURL.absoluteString
        if baseURLString.hasSuffix("/") {
            baseURLString = String(baseURLString.dropLast())
        }
        
        guard let normalizedBaseURL = URL(string: baseURLString) else {
            return nil
        }
        
        let imagePath = "Items/\(id)/Images/\(imageType)"
        var components = URLComponents(url: normalizedBaseURL.appendingPathComponent(imagePath), resolvingAgainstBaseURL: false)!
        
        var queryItems: [URLQueryItem] = []
        
        if let maxWidth = maxWidth {
            queryItems.append(URLQueryItem(name: "maxWidth", value: "\(maxWidth)"))
        }
        
        // Jellyfin doesn't use tag parameter in URL, but we accept it for API consistency
        // The tag is used for cache validation on the client side if needed
        
        if let token = accessToken {
            queryItems.append(URLQueryItem(name: "api_key", value: token))
        }
        
        components.queryItems = queryItems.isEmpty ? nil : queryItems
        
        return components.url
    }
}
