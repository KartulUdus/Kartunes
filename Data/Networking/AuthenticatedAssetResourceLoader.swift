
import Foundation
import AVFoundation

/// Custom resource loader delegate that adds authentication headers to streaming requests
final class AuthenticatedAssetResourceLoader: NSObject, AVAssetResourceLoaderDelegate {
    private let logger = Log.make(.networking)
    
    private let accessToken: String
    private let userId: String?
    private var activeRequests: [AVAssetResourceLoadingRequest] = [] // Keep strong references
    var onHTTPError: ((Int, URL) -> Void)? // statusCode, url
    
    init(accessToken: String, userId: String?) {
        self.accessToken = accessToken
        self.userId = userId
        super.init()
    }
    
    func resourceLoader(_ resourceLoader: AVAssetResourceLoader, shouldWaitForLoadingOfRequestedResource loadingRequest: AVAssetResourceLoadingRequest) -> Bool {
        guard let url = loadingRequest.request.url else {
            logger.warning("No URL in loading request")
            return false
        }
        
        let hasContentInfo = loadingRequest.contentInformationRequest != nil
        let hasDataRequest = loadingRequest.dataRequest != nil
        
        logger.debug("Received request for scheme: \(url.scheme ?? "nil")")
        logger.debug("  - Has content info request: \(hasContentInfo)")
        logger.debug("  - Has data request: \(hasDataRequest)")
        
        // Check if this is our custom scheme
        if url.scheme == "jellyfin" {
            // Keep strong reference to prevent deallocation
            activeRequests.append(loadingRequest)
            
            // Extract original URL from path
            // Format: jellyfin://secure-or-insecure/host/path?query
            let path = url.path
            let isSecure = url.host == "secure"
            
            logger.debug("Parsing URL - scheme: \(url.scheme ?? "nil"), host: \(url.host ?? "nil"), path: \(path)")
            
            // Reconstruct original URL
            // Path format: /host/path/to/resource
            let pathComponents = path.components(separatedBy: "/").filter { !$0.isEmpty }
            guard pathComponents.count >= 1 else {
                logger.error("Invalid URL path: \(path)")
                activeRequests.removeAll { $0 === loadingRequest }
                return false
            }
            
            let host = pathComponents[0]
            let restOfPath = "/" + pathComponents.dropFirst().joined(separator: "/")
            
            logger.debug("Extracted host: '\(host)', restOfPath: '\(restOfPath)'")
            
            // Build URL string manually to ensure host is preserved correctly
            let scheme = isSecure ? "https" : "http"
            var urlString = "\(scheme)://\(host)\(restOfPath)"
            if let query = url.query {
                urlString += "?\(query)"
            }
            
            guard let originalURL = URL(string: urlString) else {
                logger.error("Failed to reconstruct URL from string: \(urlString)")
                logger.debug("   - Original URL: \(url)")
                activeRequests.removeAll { $0 === loadingRequest }
                return false
            }
            
            logger.debug("Reconstructed URL: \(originalURL.absoluteString)")
            logger.debug("Loading \(originalURL)")
            
            // Handle content information request first
            if let contentRequest = loadingRequest.contentInformationRequest {
                var infoRequest = URLRequest(url: originalURL)
                infoRequest.httpMethod = "HEAD" // Just get headers
                addAuthHeaders(to: &infoRequest)
                
                logger.debug("Requesting content info for \(originalURL)")
                
                let infoTask = URLSession.shared.dataTask(with: infoRequest) { _, response, error in
                    if let error = error {
                        self.logger.error("Content info error: \(error.localizedDescription)")
                        return
                    }
                    
                    guard let httpResponse = response as? HTTPURLResponse else {
                        self.logger.error("Invalid content info response")
                        return
                    }
                    
                    self.logger.debug("Content info - status: \(httpResponse.statusCode)")
                    
                    if var contentType = httpResponse.value(forHTTPHeaderField: "Content-Type") {
                        // Fix content type for M4A files - AVPlayer expects audio/mp4 or audio/x-m4a
                        // Jellyfin sometimes returns audio/aac which AVPlayer doesn't recognize
                        if contentType == "audio/aac" || contentType.contains("aac") {
                            // Check if URL indicates M4A container
                            if originalURL.pathExtension == "m4a" || originalURL.absoluteString.contains(".m4a") {
                                contentType = "audio/mp4" // M4A is MP4 audio container
                                self.logger.debug("Fixed content type to audio/mp4 for M4A file")
                            }
                        }
                        contentRequest.contentType = contentType
                        self.logger.debug("Content type: \(contentType)")
                    }
                    if let contentLength = httpResponse.value(forHTTPHeaderField: "Content-Length"),
                       let length = Int64(contentLength) {
                        contentRequest.contentLength = length
                        self.logger.debug("Content length: \(length)")
                    }
                    contentRequest.isByteRangeAccessSupported = true
                }
                infoTask.resume()
            }
            
            // Handle data request
            if let dataRequest = loadingRequest.dataRequest {
                let requestedOffset = Int(dataRequest.requestedOffset)
                let requestedLength = dataRequest.requestedLength
                
                logger.debug("Data request received")
                logger.debug("  - Offset: \(requestedOffset)")
                logger.debug("  - Length: \(requestedLength) (Int.max = \(Int.max))")
                logger.debug("  - Current offset: \(dataRequest.currentOffset)")
                
                var request = URLRequest(url: originalURL)
                addAuthHeaders(to: &request)
                
                // Add range header if specified
                // Note: requestedLength can be Int.max for full file, or 0 for unknown
                // For streaming, we should limit chunk size, but provide enough for format detection
                let maxChunkSize = 5 * 1024 * 1024 // 5MB chunks - enough for format detection
                let initialChunkSize = 512 * 1024 // 512KB for initial header reads
                
                if requestedLength > 0 && requestedLength != Int.max {
                    // For small requests (like header reads), honor them exactly
                    if requestedLength <= initialChunkSize {
                        let rangeEnd = requestedOffset + requestedLength - 1
                        let range = "bytes=\(requestedOffset)-\(rangeEnd)"
                        request.setValue(range, forHTTPHeaderField: "Range")
                        logger.debug("Requesting exact range: \(range)")
                    } else {
                        // For large requests, limit to chunk size for streaming
                        let actualLength = min(requestedLength, maxChunkSize)
                        let rangeEnd = requestedOffset + actualLength - 1
                        let range = "bytes=\(requestedOffset)-\(rangeEnd)"
                        request.setValue(range, forHTTPHeaderField: "Range")
                        logger.debug("Requesting range: \(range) (limited from \(requestedLength))")
                    }
                } else {
                    // For full file or unknown length, request initial chunk
                    let chunkSize = requestedOffset == 0 ? maxChunkSize : maxChunkSize
                    let rangeEnd = requestedOffset + chunkSize - 1
                    let range = "bytes=\(requestedOffset)-\(rangeEnd)"
                    request.setValue(range, forHTTPHeaderField: "Range")
                    logger.debug("Requesting chunk from offset \(requestedOffset) (size: \(chunkSize) bytes)")
                }
                
                // Perform the request
                logger.debug("Starting data task for \(originalURL)")
                logger.debug("Request headers: \(request.allHTTPHeaderFields ?? [:])")
                
                // Capture loadingRequest strongly to prevent deallocation
                let task = URLSession.shared.dataTask(with: request) { [weak self, loadingRequest] data, response, error in
                    guard let self = self else { return }
                    self.logger.debug("Data task completed")
                    
                    // loadingRequest is captured strongly, so it should still be valid
                    
                    if let error = error {
                        self.logger.error("error: \(error.localizedDescription)")
                        if let nsError = error as NSError? {
                            self.logger.debug("   Error domain: \(nsError.domain), code: \(nsError.code)")
                            self.logger.debug("   User info: \(nsError.userInfo)")
                        }
                        loadingRequest.finishLoading(with: error)
                        self.activeRequests.removeAll { $0 === loadingRequest }
                        return
                    }
                    
                    guard let data = data else {
                        let error = NSError(domain: "Kartunes", code: -1, userInfo: [NSLocalizedDescriptionKey: "No data received"])
                        self.logger.error("No data received for \(originalURL)")
                        loadingRequest.finishLoading(with: error)
                        self.activeRequests.removeAll { $0 === loadingRequest }
                        return
                    }
                    
                    guard let httpResponse = response as? HTTPURLResponse else {
                        let error = NSError(domain: "Kartunes", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid response"])
                        self.logger.error("Invalid response for \(originalURL)")
                        loadingRequest.finishLoading(with: error)
                        self.activeRequests.removeAll { $0 === loadingRequest }
                        return
                    }
                    
                    self.logger.debug("Received \(data.count) bytes, status: \(httpResponse.statusCode)")
                    
                    // Check for HTTP errors
                    if httpResponse.statusCode >= 400 {
                        let error = NSError(domain: "Kartunes", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "HTTP \(httpResponse.statusCode)"])
                        self.logger.error("HTTP error \(httpResponse.statusCode) for \(originalURL)")
                        
                        // Notify about 404 errors
                        if httpResponse.statusCode == 404 {
                            onHTTPError?(404, originalURL)
                        }
                        
                        loadingRequest.finishLoading(with: error)
                        self.activeRequests.removeAll { $0 === loadingRequest }
                        return
                    }
                    
                    // Provide the data to the loading request
                    let requestedOffset = Int(dataRequest.requestedOffset)
                    let requestedLength = dataRequest.requestedLength
                    
                    self.logger.debug("Requested offset: \(requestedOffset), length: \(requestedLength), data size: \(data.count)")
                    
                    // Handle range requests
                    // Note: requestedLength can be Int.max for full file requests, or a small number for initial header reads
                    // For streaming, we provide the data we received, which may be a chunk
                    let dataToProvide: Data
                    
                    if requestedOffset < data.count {
                        // Provide data starting from requested offset
                        let availableLength = data.count - requestedOffset
                        let provideLength = min(requestedLength == Int.max ? availableLength : Int(requestedLength), availableLength)
                        let endOffset = requestedOffset + provideLength
                        
                        if endOffset <= data.count {
                            dataToProvide = data.subdata(in: requestedOffset..<endOffset)
                            self.logger.debug("Providing \(dataToProvide.count) bytes to player (range: \(requestedOffset)-\(endOffset-1))")
                        } else {
                            // Provide what we have
                            dataToProvide = data.subdata(in: requestedOffset..<data.count)
                            self.logger.debug("Providing \(dataToProvide.count) bytes to player (partial range: \(requestedOffset)-\(data.count-1))")
                        }
                    } else if requestedOffset == 0 {
                        // Provide all data we received
                        dataToProvide = data
                        self.logger.debug("Providing full \(data.count) bytes to player")
                    } else {
                        self.logger.warning("Requested offset \(requestedOffset) is beyond data size \(data.count)")
                        // Provide empty data - AVPlayer will request more
                        dataToProvide = Data()
                        self.logger.debug("Providing empty data, player will request more")
                    }
                    
                    // Provide the data to the player
                    guard !dataToProvide.isEmpty else {
                        self.logger.warning("No data to provide")
                        let error = NSError(domain: "Kartunes", code: -1, userInfo: [NSLocalizedDescriptionKey: "No data available"])
                        loadingRequest.finishLoading(with: error)
                        self.activeRequests.removeAll { $0 === loadingRequest }
                        return
                    }
                    
                    dataRequest.respond(with: dataToProvide)
                    self.logger.debug("Data provided to player (\(dataToProvide.count) bytes)")
                    
                    // Always finish the request after providing data
                    // AVPlayer will make new requests for additional chunks as needed for streaming
                    loadingRequest.finishLoading()
                    self.activeRequests.removeAll { $0 === loadingRequest }
                    self.logger.debug("Request finished, player will request more if needed")
                }
                
                task.resume()
            }
            
            return true
        }
        
        return false
    }
    
    private func addAuthHeaders(to request: inout URLRequest) {
        // Add Jellyfin authentication headers
        let deviceId = UserDefaults.standard.string(forKey: "JellyfinDeviceId") ?? UUID().uuidString
        UserDefaults.standard.set(deviceId, forKey: "JellyfinDeviceId")
        
        let authHeader = "MediaBrowser Client=\"Kartunes\", Device=\"iOS\", DeviceId=\"\(deviceId)\", Version=\"1.0.0\""
        let tokenHeader = "MediaBrowser Token=\"\(accessToken)\""
        
        request.setValue(authHeader, forHTTPHeaderField: "X-Emby-Authorization")
        request.setValue(tokenHeader, forHTTPHeaderField: "Authorization")
        
        if let userId = userId {
            request.setValue(userId, forHTTPHeaderField: "X-Emby-User-Id")
        }
        
        logger.debug("Added auth headers - Token: \(accessToken.prefix(10))..., UserId: \(userId ?? "nil")")
    }
}

/// Helper to create authenticated streaming URLs
extension URL {
    /// Converts a Jellyfin URL to use custom scheme for authenticated streaming
    static func authenticatedJellyfinStream(from url: URL, accessToken: String, userId: String?) -> URL {
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
}

