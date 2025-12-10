
import Foundation
@preconcurrency import CoreData

final class MediaServerAuthRepository: AuthRepository {
    private let apiClient: MediaServerAPIClient
    private let coreDataStack: CoreDataStack
    private let logger: AppLogger
    
    init(apiClient: MediaServerAPIClient, coreDataStack: CoreDataStack = .shared, logger: AppLogger = Log.make(.auth)) {
        self.apiClient = apiClient
        self.coreDataStack = coreDataStack
        self.logger = logger
    }
    
    func addServer(host: URL, username: String, password: String, friendlyName: String, serverType: MediaServerType = .jellyfin) async throws -> Server {
        let (finalURL, userId, accessToken) = try await apiClient.authenticate(host: host, username: username, password: password)
        
        // Use the final URL (after redirects) for the server
        let server = Server(
            id: UUID(),
            name: friendlyName,
            baseURL: finalURL,
            username: username,
            userId: userId,
            accessToken: accessToken,
            serverType: serverType
        )
        
        // Save to Core Data
        let context = coreDataStack.newBackgroundContext()
        try await context.perform {
            // Check if server with this URL already exists (use finalURL, not original host)
            let existingRequest: NSFetchRequest<CDServer> = CDServer.fetchRequest()
            existingRequest.predicate = NSPredicate(format: "baseURL == %@", finalURL.absoluteString)
            let existing = try? context.fetch(existingRequest).first
            
            if let existing = existing {
                // Update existing server
                existing.id = server.id
                existing.name = server.name
                existing.username = server.username
                existing.userId = server.userId
                existing.accessToken = server.accessToken
                existing.serverType = server.serverType
            } else {
                // Create new server
                _ = CoreDataServerHelper.fromDomain(server, in: context)
            }
            
            try context.save()
        }
        
        // Report capabilities after successful authentication
        Task {
            try? await apiClient.reportCapabilities()
        }
        
        return server
    }
    
    func listServers() async throws -> [Server] {
        let context = coreDataStack.viewContext
        return try await context.perform {
            let cdServers = try CoreDataServerHelper.fetchAll(in: context)
            return cdServers.map { CoreDataServerHelper.toDomain($0) }
        }
    }
    
    func setActiveServer(_ server: Server) async {
        let context = coreDataStack.newBackgroundContext()
        try? await context.perform {
            // Set all servers to inactive
            let allRequest: NSFetchRequest<CDServer> = CDServer.fetchRequest()
            let allServers = try context.fetch(allRequest)
            for cdServer in allServers {
                cdServer.isActive = false
            }
            
            // Set the selected server as active
            if let cdServer = try CoreDataServerHelper.findBy(id: server.id, in: context) {
                cdServer.isActive = true
            } else {
                // Server doesn't exist, create it
                let newServer = CoreDataServerHelper.fromDomain(server, in: context)
                newServer.isActive = true
            }
            
            try context.save()
        }
    }
    
    func deactivateAllServers() async {
        let context = coreDataStack.newBackgroundContext()
        try? await context.perform {
            let allRequest: NSFetchRequest<CDServer> = CDServer.fetchRequest()
            let allServers = try context.fetch(allRequest)
            for cdServer in allServers {
                cdServer.isActive = false
            }
            try context.save()
            self.logger.debug("Auth: deactivated all servers")
        }
    }
    
    func deleteServer(serverId: UUID) async {
        let context = coreDataStack.newBackgroundContext()
        try? await context.perform {
            guard let cdServer = try CoreDataServerHelper.findBy(id: serverId, in: context) else {
                self.logger.warning("Auth: server not found for deletion: \(serverId)")
                return
            }
            
            // Get all track IDs for this server before deletion
            let trackRequest: NSFetchRequest<CDTrack> = CDTrack.fetchRequest()
            trackRequest.predicate = NSPredicate(format: "server == %@", cdServer)
            let serverTracks = (try? context.fetch(trackRequest)) ?? []
            let trackIds = Set(serverTracks.compactMap { $0.id })
            
            // Delete the server and all related data (tracks, albums, artists, genres, playlists)
            // CoreData will cascade delete all related entities due to deletionRule="Cascade"
            let serverName = cdServer.name ?? "Unknown"
            self.logger.debug("Auth: deleting server '\(serverName)' and all related data")
            context.delete(cdServer)
            
            try context.save()
            self.logger.info("Auth: deleted server and related data")
            
            // Clean up downloads for all tracks from this server
            Task { @MainActor in
                OfflineDownloadManager.shared.cleanupDownloads(for: trackIds)
                self.logger.info("Auth: cleaned up downloads for deleted server")
            }
        }
    }
    
    func getActiveServer() async throws -> Server {
        let context = coreDataStack.viewContext
        return try await context.perform {
            guard let cdServer = try CoreDataServerHelper.fetchActive(in: context) else {
                throw AuthRepositoryError.noActiveServer
            }
            return CoreDataServerHelper.toDomain(cdServer)
        }
    }
    
    func updateServerURL(serverId: UUID, newURL: URL) async {
        let context = coreDataStack.newBackgroundContext()
        await context.perform {
            if let cdServer = try? CoreDataServerHelper.findBy(id: serverId, in: context) {
                cdServer.baseURL = newURL.absoluteString
                try? context.save()
                self.logger.debug("Auth: updated server URL to \(newURL.absoluteString)")
            }
        }
    }
}

enum AuthRepositoryError: Error {
    case noActiveServer
}

