
import Foundation

/// Public system info response from Jellyfin/Emby servers
struct PublicSystemInfo: Decodable {
    let productName: String?
    let serverName: String?
    let version: String?
    let localAddress: String?
    
    enum CodingKeys: String, CodingKey {
        case productName = "ProductName"
        case serverName = "ServerName"
        case version = "Version"
        case localAddress = "LocalAddress"
    }
}

/// Result of server detection
struct ServerDetectionResult {
    let serverType: MediaServerType
    let baseURL: URL
    let serverName: String?
    let version: String?
}

/// Service for detecting Jellyfin/Emby server type
enum ServerDetectionService {
    private static let logger = Log.make(.serverDetect)
    /// Detects the server type by probing the System/Info/Public endpoint
    /// - Parameter userURL: The URL entered by the user
    /// - Returns: A tuple of (detected server type, normalized base URL, server info)
    /// - Throws: Error if no compatible server is detected
    static func detectServerType(from userURL: URL) async throws -> ServerDetectionResult {
        // Normalize the base URL (remove trailing slash)
        var components = URLComponents(url: userURL, resolvingAgainstBaseURL: false)!
        var path = components.path
        
        // Remove trailing slash
        if path.hasSuffix("/") {
            path = String(path.dropLast())
        }
        components.path = path
        components.query = nil
        components.fragment = nil
        
        guard let normalizedBase = components.url else {
            throw ServerDetectionError.invalidURL
        }
        
        var candidateBases: [URL] = []
        var seenCandidates = Set<URL>()
        func appendCandidate(_ url: URL?) {
            guard let url = url, !seenCandidates.contains(url) else { return }
            candidateBases.append(url)
            seenCandidates.insert(url)
        }

        appendCandidate(normalizedBase)

        if let scheme = components.scheme?.lowercased() {
            switch scheme {
            case "https":
                var httpComponents = components
                httpComponents.scheme = "http"
                appendCandidate(httpComponents.url)
            case "http":
                var httpsComponents = components
                httpsComponents.scheme = "https"
                appendCandidate(httpsComponents.url)
            default:
                break
            }
        } else {
            var httpComponents = components
            httpComponents.scheme = "http"
            appendCandidate(httpComponents.url)
            var httpsComponents = components
            httpsComponents.scheme = "https"
            appendCandidate(httpsComponents.url)
        }

        var lastError: Error = ServerDetectionError.noCompatibleServer
        for base in candidateBases {
            do {
                let result = try await probeWithEmbyFallback(baseURL: base)
                return result
            } catch {
                lastError = error
                Self.logger.warning("Detection attempt failed for \(base.absoluteString): \(error.localizedDescription)")
            }
        }

        throw lastError
    }
    
    private static func probeWithEmbyFallback(baseURL: URL) async throws -> ServerDetectionResult {
        // Try the provided base first
        do {
            return try await probe(baseURL: baseURL)
        } catch {
            // If the failure was due to unknown product, try /emby before surfacing the error
            if case ServerDetectionError.unknownServerType = error {
                Self.logger.debug("Probe succeeded but type unknown for \(baseURL.absoluteString), trying /emby path")
            }
            // Append /emby and retry if not already present
            if var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false),
               !components.path.lowercased().contains("/emby") {
                let currentPath = components.path
                if currentPath.isEmpty {
                    components.path = "/emby"
                } else if currentPath.hasSuffix("/") {
                    components.path = currentPath + "emby"
                } else {
                    components.path = currentPath + "/emby"
                }
                if let embyURL = components.url {
                    return try await probe(baseURL: embyURL)
                }
            }
            throw error
        }
    }

    /// Probes a specific base URL for server information
    private static func probe(baseURL: URL) async throws -> ServerDetectionResult {
        let probeURL = baseURL.appendingPathComponent("System/Info/Public")
        
        var request = URLRequest(url: probeURL)
        request.httpMethod = "GET"
        request.timeoutInterval = 10.0
        
        Self.logger.debug("Probing \(probeURL.absoluteString)")
        
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            Self.logger.warning("Probe failed for \(probeURL.absoluteString): \(error.localizedDescription)")
            throw ServerDetectionError.networkError(error)
        }
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ServerDetectionError.invalidResponse
        }
        
        guard httpResponse.statusCode == 200 else {
            Self.logger.warning("Probe returned status \(httpResponse.statusCode) for \(probeURL.absoluteString)")
            throw ServerDetectionError.httpError(statusCode: httpResponse.statusCode)
        }
        
        // Log raw response for debugging
        if let responseString = String(data: data, encoding: .utf8) {
            Self.logger.debug("Raw response: \(responseString)")
        }
        
        // Decode the response
        let decoder = JSONDecoder()
        let info: PublicSystemInfo
        do {
            info = try decoder.decode(PublicSystemInfo.self, from: data)
        } catch {
            Self.logger.warning("Failed to decode response: \(error.localizedDescription)")
            // Try to decode as a generic dictionary to see what we got
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                Self.logger.debug("Response keys: \(json.keys.joined(separator: ", "))")
            }
            throw ServerDetectionError.decodingError(error)
        }
        
        // Log all fields for debugging
        Self.logger.debug("Decoded info - ProductName: '\(info.productName ?? "nil")', ServerName: '\(info.serverName ?? "nil")', Version: '\(info.version ?? "nil")'")
        
        // Determine server type from ProductName
        let productName = info.productName?.lowercased() ?? ""
        let detectedType: MediaServerType?
        
        if productName.contains("jellyfin") {
            detectedType = .jellyfin
            Self.logger.info("Detected Jellyfin server")
        } else if productName.contains("emby") {
            detectedType = .emby
            Self.logger.info("Detected Emby server")
        } else {
            // Unknown product - cannot determine type
            Self.logger.warning("Unknown product name '\(info.productName ?? "nil")', cannot determine server type")
            detectedType = nil
        }
        
        // Only return result if we successfully detected the type
        guard let type = detectedType else {
            throw ServerDetectionError.unknownServerType
        }
        
        return ServerDetectionResult(
            serverType: type,
            baseURL: baseURL,
            serverName: info.serverName,
            version: info.version
        )
    }
}

enum ServerDetectionError: LocalizedError {
    case invalidURL
    case networkError(Error)
    case invalidResponse
    case httpError(statusCode: Int)
    case decodingError(Error)
    case unknownServerType
    case noCompatibleServer
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid server URL"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .invalidResponse:
            return "Invalid response from server"
        case .httpError(let statusCode):
            if statusCode == 404 {
                return "Server not found at this address"
            }
            return "HTTP error \(statusCode)"
        case .decodingError(let error):
            return "Failed to parse server response: \(error.localizedDescription)"
        case .unknownServerType:
            return "Could not determine server type. The server responded but ProductName was not recognized."
        case .noCompatibleServer:
            return "No compatible server detected. Please check the server URL and ensure it's a Jellyfin or Emby server."
        }
    }
}
