import Foundation
import AVFoundation
import CoreData

/// Manages offline downloads for tracks
@objc final class OfflineDownloadManager: NSObject, URLSessionDownloadDelegate {
    static let shared = OfflineDownloadManager()
    
    private let logger = Log.make(.storage)
    private var downloadSession: URLSession!
    private var activeDownloads: [String: URLSessionDownloadTask] = [:]
    private var downloadProgress: [String: Double] = [:]
    private var progressCallbacks: [String: (Double) -> Void] = [:]
    
    private let downloadsDirectory: URL
    
    private override init() {
        // Set up downloads directory
        let fileManager = FileManager.default
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        downloadsDirectory = appSupport.appendingPathComponent("Kartunes/Downloads", isDirectory: true)
        
        // Create directory if it doesn't exist
        try? fileManager.createDirectory(at: downloadsDirectory, withIntermediateDirectories: true)
        
        super.init()
        
        // Configure URLSession for downloads
        // Use default configuration (not background) for foreground downloads
        let config = URLSessionConfiguration.default
        config.allowsCellularAccess = true
        config.waitsForConnectivity = true
        config.timeoutIntervalForRequest = 60.0
        config.timeoutIntervalForResource = 300.0
        // Use a background serial queue for delegate callbacks
        // URLSession delegate methods are called on this queue, then we dispatch to main actor
        let delegateQueue = OperationQueue()
        delegateQueue.maxConcurrentOperationCount = 1
        delegateQueue.name = "com.kartul.kartunes.downloads"
        delegateQueue.qualityOfService = .utility
        // IMPORTANT: URLSession retains its delegate, so we need to ensure self is properly retained
        // The delegate must be set to self (which is already an NSObject subclass)
        downloadSession = URLSession(configuration: config, delegate: self, delegateQueue: delegateQueue)
        
        // Verify delegate is set correctly
        assert(downloadSession.delegate === self, "URLSession delegate must be self")
    }
    
    // MARK: - Public API
    
    /// Get the local file URL for a track
    @MainActor
    func localFileURL(for trackId: String) -> URL {
        return downloadsDirectory.appendingPathComponent("\(trackId).m4a")
    }
    
    /// Check if a track is downloaded
    @MainActor
    func isDownloaded(trackId: String) -> Bool {
        let fileURL = localFileURL(for: trackId)
        return FileManager.default.fileExists(atPath: fileURL.path)
    }
    
    /// Start downloading a track
    @MainActor
    func startDownload(
        for track: Track,
        apiClient: MediaServerAPIClient,
        progressCallback: @escaping (Double) -> Void
    ) async {
        let trackId = track.id
        
        // Check if already downloading
        if activeDownloads[trackId] != nil {
            logger.warning("Download already in progress for track: \(trackId)")
            return
        }
        
        // Check if already downloaded
        if isDownloaded(trackId: trackId) {
            logger.info("Track already downloaded: \(trackId)")
            DownloadStatusManager.setStatus(.downloaded, for: trackId)
            progressCallback(1.0)
            return
        }
        
        // Build download URL (transcoded to AAC)
        let downloadURL: URL
        if track.serverId.uuidString.contains("jellyfin") || apiClient.serverType == .jellyfin {
            // Jellyfin: Use universal endpoint with AAC codec
            downloadURL = buildJellyfinDownloadURL(trackId: trackId, apiClient: apiClient)
        } else {
            // Emby: Use stream endpoint with AAC codec
            downloadURL = buildEmbyDownloadURL(trackId: trackId, apiClient: apiClient)
        }
        
        logger.info("Starting download for track \(trackId): \(downloadURL.absoluteString)")
        
        // Set status to queued, then downloading
        DownloadStatusManager.setStatus(.queued, for: trackId)
        progressCallbacks[trackId] = progressCallback
        
        // Create download request with proper headers
        var request = URLRequest(url: downloadURL)
        request.httpMethod = "GET"
        request.setValue("application/octet-stream", forHTTPHeaderField: "Accept")
        
        // Add authentication headers based on server type
        // Both Jellyfin and Emby use X-Emby-Authorization header format
        let deviceId: String
        if let jellyfinClient = apiClient as? DefaultJellyfinAPIClient {
            deviceId = jellyfinClient.deviceId
        } else if let embyClient = apiClient as? DefaultEmbyAPIClient {
            deviceId = embyClient.deviceId
        } else {
            // Fallback to a default device ID
            deviceId = "BF9B3151-5103-41BF-B330-D50DD91A0E52"
        }
        
        let authHeader = "MediaBrowser Client=\"Kartunes\", Device=\"iOS\", DeviceId=\"\(deviceId)\", Version=\"1.0.0\""
        request.setValue(authHeader, forHTTPHeaderField: "X-Emby-Authorization")
        
        if let token = apiClient.accessToken, !token.isEmpty {
            if apiClient.serverType == .jellyfin {
                // Jellyfin uses Authorization header with MediaBrowser Token format
                let tokenHeader = "MediaBrowser Token=\"\(token)\""
                request.setValue(tokenHeader, forHTTPHeaderField: "Authorization")
            } else {
                // Emby uses X-Emby-Token header
                request.setValue(token, forHTTPHeaderField: "X-Emby-Token")
            }
        }
        
        if let userId = apiClient.userId {
            request.setValue(userId, forHTTPHeaderField: "X-Emby-User-Id")
        }
        
        // Log request details for debugging
        logger.debug("Download request headers: \(request.allHTTPHeaderFields ?? [:])")
        
        // Create download task
        let task = downloadSession.downloadTask(with: request)
        activeDownloads[trackId] = task
        DownloadStatusManager.setStatus(.downloading, for: trackId)
        downloadProgress[trackId] = 0.0
        
        logger.debug("Download task created for track \(trackId), resuming...")
        
        // Verify delegate is still set
        if downloadSession.delegate !== self {
            logger.error("WARNING: URLSession delegate is not self! This will prevent delegate methods from being called.")
        }
        
        // Notify that download started immediately
        NotificationCenter.default.post(name: .downloadStarted, object: nil)
        
        // Also post initial progress notification
        NotificationCenter.default.post(
            name: .downloadProgress,
            object: nil,
            userInfo: ["trackId": trackId, "progress": 0.0]
        )
        
        task.resume()
        
        // Periodically check task progress and manually trigger updates if delegate isn't being called
        Task {
            var lastBytesReceived: Int64 = 0
            while task.state == .running {
                try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
                let currentBytes = task.countOfBytesReceived
                let expectedBytes = task.countOfBytesExpectedToReceive
                
                if currentBytes > lastBytesReceived && expectedBytes > 0 {
                    // Progress is happening but delegate might not be called
                    let progress = Double(currentBytes) / Double(expectedBytes)
                    
                    // Manually update progress if delegate isn't being called
                    await MainActor.run {
                        downloadProgress[trackId] = progress
                        progressCallbacks[trackId]?(progress)
                        NotificationCenter.default.post(
                            name: .downloadProgress,
                            object: nil,
                            userInfo: ["trackId": trackId, "progress": progress]
                        )
                    }
                    lastBytesReceived = currentBytes
                }
                
                if task.state != .running {
                    // Download completed - check if file was saved
                    // If download finished successfully, manually trigger completion check
                    if task.state == .completed {
                        // Give it a moment for didFinishDownloadingTo to be called
                        try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
                        
                        // Check if file exists at final location
                        let fileURL = await MainActor.run { localFileURL(for: trackId) }
                        let fileManager = FileManager.default
                        let fileExists = fileManager.fileExists(atPath: fileURL.path)
                        
                        if !fileExists {
                            // File doesn't exist - didFinishDownloadingTo wasn't called
                            // This is a workaround: manually download the data using a data task
                            logger.warning("File not found at final location, didFinishDownloadingTo wasn't called. Using workaround...")
                            
                            if let response = task.response as? HTTPURLResponse,
                               response.statusCode == 200 {
                                logger.debug("HTTP response was successful, manually downloading file data...")
                                
                                // Create a new data task to get the file
                                // This is a workaround since didFinishDownloadingTo isn't being called
                                if let originalRequest = task.originalRequest {
                                    // Use the same authenticated request
                                    let dataTask = downloadSession.dataTask(with: originalRequest) { [weak self] data, response, error in
                                        Task { @MainActor in
                                            guard let self = self else { return }
                                            
                                            if let error = error {
                                                self.logger.error("Failed to manually download file: \(error.localizedDescription)")
                                                DownloadStatusManager.setStatus(.failed, for: trackId)
                                                self.activeDownloads.removeValue(forKey: trackId)
                                                self.downloadProgress.removeValue(forKey: trackId)
                                                self.progressCallbacks.removeValue(forKey: trackId)
                                                return
                                            }
                                            
                                            guard let data = data, !data.isEmpty else {
                                                self.logger.error("No data received in manual download")
                                                DownloadStatusManager.setStatus(.failed, for: trackId)
                                                self.activeDownloads.removeValue(forKey: trackId)
                                                self.downloadProgress.removeValue(forKey: trackId)
                                                self.progressCallbacks.removeValue(forKey: trackId)
                                                return
                                            }
                                            
                                            // Validate the downloaded data is actually a valid audio file
                                            guard data.count > 8 else {
                                                self.logger.error("Downloaded file is too small")
                                                DownloadStatusManager.setStatus(.failed, for: trackId)
                                                self.activeDownloads.removeValue(forKey: trackId)
                                                self.downloadProgress.removeValue(forKey: trackId)
                                                self.progressCallbacks.removeValue(forKey: trackId)
                                                return
                                            }
                                            
                                            // Check for FLAC files (starts with "fLaC")
                                            if data.count >= 4 {
                                                let flacSignature = data.prefix(4)
                                                if String(data: flacSignature, encoding: .ascii) == "fLaC" {
                                                    self.logger.error("Downloaded file is FLAC format, not M4A/AAC. Server did not transcode despite requesting container=m4a&audioCodec=aac")
                                                    DownloadStatusManager.setStatus(.failed, for: trackId)
                                                    self.activeDownloads.removeValue(forKey: trackId)
                                                    self.downloadProgress.removeValue(forKey: trackId)
                                                    self.progressCallbacks.removeValue(forKey: trackId)
                                                    return
                                                }
                                            }
                                            
                                            // Check if it starts with HLS playlist markers
                                            if let firstLine = String(data: data.prefix(100), encoding: .utf8),
                                               firstLine.contains("#EXTM3U") || firstLine.contains("#EXT-X") {
                                                self.logger.error("File is HLS playlist (starts with: \(firstLine.prefix(50)))")
                                                DownloadStatusManager.setStatus(.failed, for: trackId)
                                                self.activeDownloads.removeValue(forKey: trackId)
                                                self.downloadProgress.removeValue(forKey: trackId)
                                                self.progressCallbacks.removeValue(forKey: trackId)
                                                return
                                            }
                                            
                                            // Check for M4A/AAC file signature (ftyp box at offset 4)
                                            // M4A files start with: [4 bytes size][4 bytes "ftyp"][4 bytes brand]
                                            var isValidM4A = false
                                            if data.count >= 12 {
                                                let ftypRange = data.subdata(in: 4..<8)
                                                if let ftyp = String(data: ftypRange, encoding: .ascii), ftyp == "ftyp" {
                                                    // Check for M4A/AAC container types
                                                    let brandRange = data.subdata(in: 8..<12)
                                                    if let brand = String(data: brandRange, encoding: .ascii) {
                                                        // Valid M4A brands
                                                        if brand == "M4A " || brand == "mp41" || brand == "isom" || brand == "M4B " {
                                                            isValidM4A = true
                                                        } else {
                                                            self.logger.warning("File has ftyp box but unknown brand: \(brand)")
                                                        }
                                                    }
                                                } else {
                                                    self.logger.warning("File doesn't have ftyp box at offset 4 (got: \(String(describing: String(data: ftypRange, encoding: .ascii))))")
                                                }
                                            }
                                            
                                            if !isValidM4A {
                                                self.logger.error("Downloaded file does not appear to be a valid M4A/AAC file. Server may not be transcoding properly.")
                                                DownloadStatusManager.setStatus(.failed, for: trackId)
                                                self.activeDownloads.removeValue(forKey: trackId)
                                                self.downloadProgress.removeValue(forKey: trackId)
                                                self.progressCallbacks.removeValue(forKey: trackId)
                                                return
                                            }
                                            
                                            // Save the file
                                            let fileURL = self.localFileURL(for: trackId)
                                            let fileManager = FileManager.default
                                            
                                            // Create directory if needed
                                            try? fileManager.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                                            
                                            do {
                                                try data.write(to: fileURL)
                                                self.logger.info("Manually saved downloaded file to \(fileURL.path), size: \(data.count) bytes")
                                                
                                                // Verify the file can be read by AVFoundation
                                                let asset = AVURLAsset(url: fileURL)
                                                do {
                                                    let isPlayable = try await asset.load(.isPlayable)
                                                    if !isPlayable {
                                                        self.logger.error("Downloaded file is not playable by AVPlayer")
                                                        try? fileManager.removeItem(at: fileURL)
                                                        DownloadStatusManager.setStatus(.failed, for: trackId)
                                                        self.activeDownloads.removeValue(forKey: trackId)
                                                        self.downloadProgress.removeValue(forKey: trackId)
                                                        self.progressCallbacks.removeValue(forKey: trackId)
                                                        return
                                                    }
                                                } catch {
                                                    self.logger.error("Error checking if file is playable: \(error.localizedDescription)")
                                                    // Continue anyway - might still work
                                                }
                                                
                                                DownloadStatusManager.setStatus(.downloaded, for: trackId)
                                                self.downloadProgress[trackId] = 1.0
                                                self.progressCallbacks[trackId]?(1.0)
                                                self.activeDownloads.removeValue(forKey: trackId)
                                                self.progressCallbacks.removeValue(forKey: trackId)
                                                
                                                // Post completion notification
                                                NotificationCenter.default.post(
                                                    name: .downloadProgress,
                                                    object: nil,
                                                    userInfo: ["trackId": trackId, "progress": 1.0]
                                                )
                                                NotificationCenter.default.post(name: .downloadStarted, object: nil)
                                            } catch {
                                                self.logger.error("Failed to save manually downloaded file: \(error.localizedDescription)")
                                                DownloadStatusManager.setStatus(.failed, for: trackId)
                                                self.activeDownloads.removeValue(forKey: trackId)
                                                self.downloadProgress.removeValue(forKey: trackId)
                                                self.progressCallbacks.removeValue(forKey: trackId)
                                            }
                                        }
                                    }
                                    dataTask.resume()
                                }
                            }
                        } else {
                            // File exists - download was successful
                            await MainActor.run {
                                DownloadStatusManager.setStatus(.downloaded, for: trackId)
                                downloadProgress[trackId] = 1.0
                                progressCallbacks[trackId]?(1.0)
                                activeDownloads.removeValue(forKey: trackId)
                                progressCallbacks.removeValue(forKey: trackId)
                                
                                // Post completion notification
                                NotificationCenter.default.post(
                                    name: .downloadProgress,
                                    object: nil,
                                    userInfo: ["trackId": trackId, "progress": 1.0]
                                )
                                NotificationCenter.default.post(name: .downloadStarted, object: nil)
                            }
                        }
                    }
                    break
                }
            }
        }
    }
    
    /// Cancel a download
    @MainActor
    func cancelDownload(for trackId: String) {
        guard let task = activeDownloads[trackId] else { return }
        task.cancel()
        activeDownloads.removeValue(forKey: trackId)
        downloadProgress.removeValue(forKey: trackId)
        progressCallbacks.removeValue(forKey: trackId)
        DownloadStatusManager.setStatus(.notDownloaded, for: trackId)
        logger.info("Cancelled download for track: \(trackId)")
    }
    
    /// Delete a downloaded track
    @MainActor
    func deleteDownload(for trackId: String) throws {
        let fileURL = localFileURL(for: trackId)
        let fileManager = FileManager.default
        
        if fileManager.fileExists(atPath: fileURL.path) {
            try fileManager.removeItem(at: fileURL)
            logger.info("Deleted download for track: \(trackId)")
        }
        
        DownloadStatusManager.removeStatus(for: trackId)
    }
    
    /// Get all downloaded track IDs
    @MainActor
    func getAllDownloadedTrackIds() -> [String] {
        let fileManager = FileManager.default
        guard let files = try? fileManager.contentsOfDirectory(at: downloadsDirectory, includingPropertiesForKeys: nil) else {
            return []
        }
        
        // Accept both .m4a and .mp4 files (both can contain AAC audio)
        return files
            .filter { 
                let ext = $0.pathExtension.lowercased()
                return ext == "m4a" || ext == "mp4"
            }
            .map { $0.deletingPathExtension().lastPathComponent }
    }
    
    /// Clean up downloads for deleted tracks
    @MainActor
    func cleanupDownloads(for existingTrackIds: Set<String>) {
        let downloadedIds = Set(getAllDownloadedTrackIds())
        let orphanedIds = downloadedIds.subtracting(existingTrackIds)
        
        for trackId in orphanedIds {
            do {
                try deleteDownload(for: trackId)
                logger.info("Cleaned up orphaned download: \(trackId)")
            } catch {
                logger.error("Failed to clean up orphaned download \(trackId): \(error.localizedDescription)")
            }
        }
        
        // Also clean up status tracking
        DownloadStatusManager.cleanupStatuses(for: existingTrackIds)
    }
    
    /// Clean up downloads for a specific server
    func cleanupDownloads(for serverId: UUID, in context: NSManagedObjectContext) {
        Task { @MainActor in
            let existingTrackIds = await context.perform {
                let request: NSFetchRequest<CDTrack> = CDTrack.fetchRequest()
                request.predicate = NSPredicate(format: "server.id == %@", serverId as CVarArg)
                
                guard let tracks = try? context.fetch(request) else { return Set<String>() }
                return Set(tracks.compactMap { $0.id })
            }
            
            // Clean up all orphaned downloads
            cleanupDownloads(for: existingTrackIds)
        }
    }
    
    // MARK: - URL Building
    
    private func buildJellyfinDownloadURL(trackId: String, apiClient: MediaServerAPIClient) -> URL {
        // For Jellyfin, use /Audio/{id}/stream for transcoded AAC downloads
        // This endpoint supports transcoding with static=true to get a complete file
        // Using /stream instead of /universal for consistency with Emby
        guard let jellyfinClient = apiClient as? DefaultJellyfinAPIClient else {
            // Fallback: try to use direct file endpoint
            return (apiClient as? JellyfinAPIClient)?.buildStreamURL(forTrackId: trackId, preferredCodec: "aac", preferredContainer: "m4a") ?? URL(string: "https://example.com")!
        }
        
        // Use /Audio/{id}/stream endpoint for transcoded downloads
        // Use lowercase parameters for consistency with Emby
        var components = URLComponents(url: jellyfinClient.baseURL.appendingPathComponent("Audio/\(trackId)/stream"), resolvingAgainstBaseURL: false)!
        
        var queryItems: [URLQueryItem] = []
        
        if let token = apiClient.accessToken, !token.isEmpty {
            queryItems.append(URLQueryItem(name: "api_key", value: token))
        }
        
        if let userId = apiClient.userId {
            queryItems.append(URLQueryItem(name: "userId", value: userId))
        }
        
        queryItems.append(URLQueryItem(name: "deviceId", value: jellyfinClient.deviceId))
        
        // Request transcoding to AAC in M4A container (lowercase params for consistency)
        // Force transcoding by explicitly requesting different codec/container than source
        // NOTE: Do NOT use static=true - it tells Jellyfin to return the original file without transcoding
        queryItems.append(URLQueryItem(name: "audioCodec", value: "aac"))
        queryItems.append(URLQueryItem(name: "container", value: "m4a"))
        queryItems.append(URLQueryItem(name: "audioBitRate", value: "320000"))
        queryItems.append(URLQueryItem(name: "maxAudioChannels", value: "2"))
        queryItems.append(URLQueryItem(name: "audioSampleRate", value: "44100"))
        queryItems.append(URLQueryItem(name: "maxAudioBitDepth", value: "16"))
        queryItems.append(URLQueryItem(name: "TranscodingMaxAudioChannels", value: "2"))
        
        components.queryItems = queryItems.isEmpty ? nil : queryItems
        
        return components.url ?? jellyfinClient.baseURL.appendingPathComponent("Audio/\(trackId)/stream")
    }
    
    private func buildEmbyDownloadURL(trackId: String, apiClient: MediaServerAPIClient) -> URL {
        // For Emby, use /Audio/{id}/stream for transcoded AAC downloads
        // Emby does NOT support /Audio/{id}/universal (Jellyfin-only)
        guard let embyClient = apiClient as? DefaultEmbyAPIClient else {
            // Fallback to stream URL
            return (apiClient as? EmbyAPIClient)?.buildStreamURL(forTrackId: trackId, preferredCodec: "aac", preferredContainer: "m4a") ?? URL(string: "https://example.com")!
        }
        
        // Use /Audio/{id}/stream endpoint for transcoded downloads
        // Note: Emby uses lowercase query parameters
        var components = URLComponents(url: embyClient.buildURL(path: "Audio/\(trackId)/stream"), resolvingAgainstBaseURL: false)!
        
        var queryItems: [URLQueryItem] = []
        
        if let token = apiClient.accessToken, !token.isEmpty {
            queryItems.append(URLQueryItem(name: "api_key", value: token))
        }
        
        if let userId = apiClient.userId {
            queryItems.append(URLQueryItem(name: "UserId", value: userId))
        }
        
        queryItems.append(URLQueryItem(name: "DeviceId", value: embyClient.deviceId))
        
        // Request transcoding to AAC in M4A container (Emby uses lowercase params)
        // Force transcoding by explicitly requesting different codec/container than source
        // NOTE: Do NOT use static=true - it tells the server to return the original file without transcoding
        queryItems.append(URLQueryItem(name: "audioCodec", value: "aac"))
        queryItems.append(URLQueryItem(name: "container", value: "m4a"))
        queryItems.append(URLQueryItem(name: "audioBitRate", value: "320000"))
        queryItems.append(URLQueryItem(name: "maxAudioChannels", value: "2"))
        queryItems.append(URLQueryItem(name: "audioSampleRate", value: "44100"))
        queryItems.append(URLQueryItem(name: "maxAudioBitDepth", value: "16"))
        queryItems.append(URLQueryItem(name: "transcodingMaxAudioChannels", value: "2"))
        
        components.queryItems = queryItems.isEmpty ? nil : queryItems
        
        return components.url ?? embyClient.buildURL(path: "Audio/\(trackId)/stream")
    }
    
    // MARK: - URLSessionDownloadDelegate
    
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let originalURL = downloadTask.originalRequest?.url else {
            return
        }
        
        guard let trackId = Self.extractTrackId(from: originalURL) else {
            return
        }
        
        // Get downloads directory path
        let fileManager = FileManager.default
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let downloadsDir = appSupport.appendingPathComponent("Kartunes/Downloads", isDirectory: true)
        
        // Check Content-Type from response to determine file extension
        // Server may return .mp4 instead of .m4a, but both contain AAC audio
        var finalExtension = "m4a" // Default to m4a
        if let httpResponse = downloadTask.response as? HTTPURLResponse,
           let contentType = httpResponse.value(forHTTPHeaderField: "Content-Type") {
            if contentType.contains("mp4") || contentType.contains("m4a") {
                finalExtension = "m4a"
            }
        } else {
            // Check the actual file extension of the downloaded file as fallback
            let downloadedExtension = location.pathExtension.lowercased()
            if downloadedExtension == "mp4" || downloadedExtension == "m4a" {
                finalExtension = "m4a"
            }
        }
        
        let destinationURL = downloadsDir.appendingPathComponent("\(trackId).\(finalExtension)")
        
        // Check if downloaded file is actually a valid audio file (not HLS playlist)
        // Read first few bytes to check for M4A/AAC signature or HLS playlist
        let isHLSPlaylist: Bool = {
            guard let data = try? Data(contentsOf: location, options: .mappedIfSafe),
                  data.count > 8 else {
                return false
            }
            
            // Check if it starts with HLS playlist markers
            if let firstLine = String(data: data.prefix(100), encoding: .utf8),
               firstLine.contains("#EXTM3U") || firstLine.contains("#EXT-X") {
                return true
            }
            
            // Check for M4A/AAC file signature (ftyp box at offset 4)
            // M4A files start with: [4 bytes size][4 bytes "ftyp"][4 bytes brand]
            if data.count >= 12 {
                let ftypRange = data.subdata(in: 4..<8)
                if let ftyp = String(data: ftypRange, encoding: .ascii), ftyp == "ftyp" {
                    // Check for M4A/AAC container types
                    if data.count >= 12 {
                        let brandRange = data.subdata(in: 8..<12)
                        if let brand = String(data: brandRange, encoding: .ascii) {
                            // Valid M4A brands
                            if brand == "M4A " || brand == "mp41" || brand == "isom" || brand == "M4B " {
                                return false // Valid M4A file
                            }
                        }
                    }
                }
            }
            
            // If it doesn't match M4A signature, it might be HLS or another format
            // For now, we'll try to move it and let AVPlayer decide
            return false
        }()
        
        if isHLSPlaylist {
            Task { @MainActor in
                DownloadStatusManager.setStatus(.failed, for: trackId)
                activeDownloads.removeValue(forKey: trackId)
                downloadProgress.removeValue(forKey: trackId)
                progressCallbacks.removeValue(forKey: trackId)
            }
            // Clean up the HLS file
            try? fileManager.removeItem(at: location)
            return
        }
        
        // Remove existing file if present
        try? fileManager.removeItem(at: destinationURL)
        
        // Verify file size before moving
        let fileAttributes = try? fileManager.attributesOfItem(atPath: location.path)
        let fileSize = (fileAttributes?[.size] as? NSNumber)?.intValue ?? 0
        
        if fileSize == 0 {
            Task { @MainActor in
                DownloadStatusManager.setStatus(.failed, for: trackId)
                activeDownloads.removeValue(forKey: trackId)
                downloadProgress.removeValue(forKey: trackId)
                progressCallbacks.removeValue(forKey: trackId)
            }
            try? fileManager.removeItem(at: location)
            return
        }
        
        // Move downloaded file to destination
        do {
            try fileManager.moveItem(at: location, to: destinationURL)
            
            // Verify the file can be read by AVFoundation (async check)
            Task {
                let asset = AVURLAsset(url: destinationURL)
                do {
                    let isPlayable = try await asset.load(.isPlayable)
                    if !isPlayable {
                        try? fileManager.removeItem(at: destinationURL)
                        await MainActor.run {
                            DownloadStatusManager.setStatus(.failed, for: trackId)
                            activeDownloads.removeValue(forKey: trackId)
                            downloadProgress.removeValue(forKey: trackId)
                            progressCallbacks.removeValue(forKey: trackId)
                        }
                        return
                    }
                } catch {
                    // Continue anyway - might still work
                }
                
                await MainActor.run {
                    DownloadStatusManager.setStatus(.downloaded, for: trackId)
                    downloadProgress[trackId] = 1.0
                    progressCallbacks[trackId]?(1.0)
                    activeDownloads.removeValue(forKey: trackId)
                    progressCallbacks.removeValue(forKey: trackId)
                    
                    // Post notification that download completed
                    NotificationCenter.default.post(
                        name: .downloadProgress,
                        object: nil,
                        userInfo: ["trackId": trackId, "progress": 1.0]
                    )
                }
            }
        } catch {
            Task { @MainActor in
                DownloadStatusManager.setStatus(.failed, for: trackId)
                activeDownloads.removeValue(forKey: trackId)
                downloadProgress.removeValue(forKey: trackId)
                progressCallbacks.removeValue(forKey: trackId)
            }
        }
    }
    
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard let originalURL = downloadTask.originalRequest?.url else {
            return
        }
        
        guard let trackId = Self.extractTrackId(from: originalURL) else {
            return
        }
        
        let progress = totalBytesExpectedToWrite > 0 
            ? Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
            : 0.0
        
        // Update progress on main actor
        Task { @MainActor in
            downloadProgress[trackId] = progress
            progressCallbacks[trackId]?(progress)
            
            // Post notification for UI updates
            NotificationCenter.default.post(
                name: .downloadProgress,
                object: nil,
                userInfo: ["trackId": trackId, "progress": progress]
            )
        }
    }
    
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let originalURL = task.originalRequest?.url,
              let trackId = Self.extractTrackId(from: originalURL) else {
            return
        }
        
        if let error = error {
            Task { @MainActor in
                DownloadStatusManager.setStatus(.failed, for: trackId)
                activeDownloads.removeValue(forKey: trackId)
                downloadProgress.removeValue(forKey: trackId)
                progressCallbacks.removeValue(forKey: trackId)
            }
        }
    }
    
    // MARK: - Helpers
    
    nonisolated private static func extractTrackId(from url: URL) -> String? {
        // Extract track ID from URL path
        // Format: /Items/{trackId}/Download or /Audio/{trackId}/universal or /Audio/{trackId}/stream
        let pathComponents = url.pathComponents
        
        // Try Items/{trackId}/Download first
        if let itemsIndex = pathComponents.firstIndex(of: "Items"),
           itemsIndex + 1 < pathComponents.count {
            return pathComponents[itemsIndex + 1]
        }
        
        // Fallback to Audio/{trackId}/...
        if let audioIndex = pathComponents.firstIndex(of: "Audio"),
           audioIndex + 1 < pathComponents.count {
            return pathComponents[audioIndex + 1]
        }
        
        return nil
    }
    
    nonisolated private static func localFileURL(for trackId: String, downloadsDirectory: URL) -> URL {
        return downloadsDirectory.appendingPathComponent("\(trackId).m4a")
    }
}

