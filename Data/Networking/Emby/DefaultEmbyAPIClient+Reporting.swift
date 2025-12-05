
import Foundation

extension DefaultEmbyAPIClient {
    func reportCapabilities() async throws {
        var request = buildRequest(path: "Sessions/Capabilities/Full", method: "POST")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let capabilities = JellyfinClientCapabilities(
            playableMediaTypes: ["Audio"],
            supportsMediaControl: true,
            supportsSync: false,
            supportsPersistentIdentifier: true
        )
        
        let encoder = JSONEncoder()
        request.httpBody = try encoder.encode(capabilities)
        
        do {
            let _: EmptyResponse = try await httpClient.request(request)
            logger.debug("Capabilities reported successfully")
        } catch {
            logger.warning("Failed to report capabilities: \(error.localizedDescription)")
        }
    }
    
    func reportPlaybackStart(itemId: String, mediaSourceId: String?, playSessionId: String, positionTicks: Int64, isPaused: Bool, playMethod: String) async throws {
        var request = buildRequest(path: "Sessions/Playing", method: "POST")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let startInfo = JellyfinPlaybackStartInfo(
            itemId: itemId,
            mediaSourceId: mediaSourceId,
            playSessionId: playSessionId,
            positionTicks: positionTicks,
            isPaused: isPaused,
            canSeek: true,
            playMethod: playMethod
        )
        
        let encoder = JSONEncoder()
        request.httpBody = try encoder.encode(startInfo)
        
        do {
            let _: EmptyResponse = try await httpClient.request(request)
            logger.debug("Playback start reported for \(itemId)")
        } catch {
            logger.warning("Failed to report playback start: \(error.localizedDescription)")
        }
    }
    
    func reportPlaybackProgress(itemId: String, mediaSourceId: String?, playSessionId: String, positionTicks: Int64, isPaused: Bool, eventName: String?) async throws {
        var request = buildRequest(path: "Sessions/Playing/Progress", method: "POST")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let progressInfo = JellyfinPlaybackProgressInfo(
            itemId: itemId,
            mediaSourceId: mediaSourceId,
            playSessionId: playSessionId,
            positionTicks: positionTicks,
            isPaused: isPaused,
            playbackRate: 1.0,
            eventName: eventName
        )
        
        let encoder = JSONEncoder()
        request.httpBody = try encoder.encode(progressInfo)
        
        do {
            let _: EmptyResponse = try await httpClient.request(request)
        } catch {
            logger.warning("Failed to report playback progress: \(error.localizedDescription)")
        }
    }
    
    func reportPlaybackStopped(itemId: String, mediaSourceId: String?, playSessionId: String, positionTicks: Int64, nextMediaType: String?) async throws {
        var request = buildRequest(path: "Sessions/Playing/Stopped", method: "POST")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let stopInfo = JellyfinPlaybackStopInfo(
            itemId: itemId,
            mediaSourceId: mediaSourceId,
            playSessionId: playSessionId,
            positionTicks: positionTicks,
            nextMediaType: nextMediaType
        )
        
        let encoder = JSONEncoder()
        request.httpBody = try encoder.encode(stopInfo)
        
        do {
            let _: EmptyResponse = try await httpClient.request(request)
            logger.debug("Playback stopped reported for \(itemId)")
        } catch {
            logger.warning("Failed to report playback stopped: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Helper Methods
    
    /// Constructs a URL by properly combining the baseURL path with a new path component
    /// This ensures paths like /emby are preserved when appending new paths
}
