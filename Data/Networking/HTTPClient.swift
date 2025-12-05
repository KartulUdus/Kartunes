
import Foundation

protocol HTTPClient {
    func request<T: Decodable>(_ endpoint: URLRequest) async throws -> T
}

struct DefaultHTTPClient: HTTPClient {
    private let session: URLSession
    private let logger: AppLogger
    
    init(session: URLSession? = nil, logger: AppLogger = Log.make(.httpClient)) {
        self.logger = logger
        if let session = session {
            self.session = session
        } else {
            // Configure session with longer timeout for large libraries
            let config = URLSessionConfiguration.default
            config.timeoutIntervalForRequest = 60.0 // Increased to 60 seconds
            config.timeoutIntervalForResource = 120.0 // Increased to 120 seconds
            self.session = URLSession(configuration: config)
        }
    }
    
    func request<T: Decodable>(_ endpoint: URLRequest) async throws -> T {
        logger.debug("Making request to \(endpoint.url?.absoluteString ?? "unknown")")
        let startTime = Date()
        
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: endpoint)
            let duration = Date().timeIntervalSince(startTime)
            logger.debug("Request completed in \(String(format: "%.2f", duration))s, response size: \(data.count) bytes")
        } catch {
            logger.error("Request failed after \(String(format: "%.2f", Date().timeIntervalSince(startTime)))s: \(error.localizedDescription)")
            throw HTTPClientError.networkError(error)
        }
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw HTTPClientError.invalidResponse
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            // Log response body for debugging
            if let responseBody = String(data: data, encoding: .utf8) {
                logger.error("HTTP Error \(httpResponse.statusCode): \(responseBody)")
            }
            throw HTTPClientError.httpError(statusCode: httpResponse.statusCode)
        }
        
        // Handle empty responses (e.g., DELETE requests)
        if data.isEmpty {
            // Try to decode as empty JSON object or return a default
            if let emptyJSON = "{}".data(using: .utf8) {
                do {
                    let decoder = JSONDecoder()
                    return try decoder.decode(T.self, from: emptyJSON)
                } catch {
                    // If T doesn't support empty JSON, throw
                    throw HTTPClientError.decodingError(error)
                }
            }
        }
        
        do {
            let decoder = JSONDecoder()
            // Jellyfin uses PascalCase, so we use default strategy
            // Individual DTOs will handle their own CodingKeys
            return try decoder.decode(T.self, from: data)
        } catch {
            throw HTTPClientError.decodingError(error)
        }
    }
}

enum HTTPClientError: LocalizedError {
    case invalidResponse
    case httpError(statusCode: Int)
    case decodingError(Error)
    case networkError(Error)
    
    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid response from server"
        case .httpError(let statusCode):
            switch statusCode {
            case 401:
                return "Unauthorized - Please check your credentials"
            case 403:
                return "Forbidden - Access denied"
            case 404:
                return "Not found - The requested resource doesn't exist"
            case 405:
                return "Method not allowed - Operation not permitted"
            case 500...599:
                return "Server error (HTTP \(statusCode))"
            default:
                return "HTTP error \(statusCode)"
            }
        case .decodingError(let error):
            return "Failed to parse response: \(error.localizedDescription)"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        }
    }
}

