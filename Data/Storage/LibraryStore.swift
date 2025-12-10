
import Foundation
import CoreData

/// Thread-safe actor wrapper for Core Data operations
/// Ensures all Core Data access is serialized and thread-safe
actor LibraryStore {
    private let container: NSPersistentContainer
    private let bgContext: NSManagedObjectContext
    nonisolated private let logger: AppLogger
    
    init(container: NSPersistentContainer) {
        self.container = container
        self.bgContext = container.newBackgroundContext()
        self.bgContext.automaticallyMergesChangesFromParent = true
        // Create logger in init to avoid calling main actor-isolated function during property initialization
        self.logger = Log.make(.storage)
    }
    
    // MARK: - Favorites/Likes
    
    /// Fetch all liked track IDs
    func fetchLikedTrackIds() throws -> Set<String> {
        return try bgContext.performAndWait {
            let request: NSFetchRequest<CDTrack> = CDTrack.fetchRequest()
            request.predicate = NSPredicate(format: "isLiked == YES")
            let likedTracks = try bgContext.fetch(request)
            return Set(likedTracks.compactMap { $0.id })
        }
    }
    
    /// Update liked status for a track
    func updateLikedStatus(trackId: String, isLiked: Bool, serverId: UUID) throws {
        try bgContext.performAndWait {
            // Find the server
            let serverRequest: NSFetchRequest<CDServer> = CDServer.fetchRequest()
            serverRequest.predicate = NSPredicate(format: "id == %@", serverId as CVarArg)
            serverRequest.fetchLimit = 1
            
            guard let server = try bgContext.fetch(serverRequest).first else {
                logger.warning("LibraryStore: Server not found for track \(trackId)")
                return
            }
            
            // Find the track
            if let cdTrack = try? CDTrack.findBy(id: trackId, server: server, in: bgContext) {
                cdTrack.isLiked = isLiked
                if bgContext.hasChanges {
                    try bgContext.save()
                }
            } else {
                logger.warning("LibraryStore: Track not found: \(trackId)")
            }
        }
    }
    
    // MARK: - Server Operations
    
    /// Fetch all servers
    func fetchServers() throws -> [CDServer] {
        return try bgContext.performAndWait {
            let request: NSFetchRequest<CDServer> = CDServer.fetchRequest()
            return try bgContext.fetch(request)
        }
    }
    
    /// Fetch active server
    func fetchActiveServer() throws -> CDServer? {
        return try bgContext.performAndWait {
            let request: NSFetchRequest<CDServer> = CDServer.fetchRequest()
            request.predicate = NSPredicate(format: "isActive == YES")
            request.fetchLimit = 1
            return try bgContext.fetch(request).first
        }
    }
    
    // MARK: - Track Operations
    
    /// Fetch tracks by various criteria (for search, filtering, etc.)
    func fetchTracks(predicate: NSPredicate, sortDescriptors: [NSSortDescriptor] = []) throws -> [CDTrack] {
        // Extract predicate format and sort descriptor info to avoid capturing non-Sendable types
        let predicateFormat = predicate.predicateFormat
        let sortDescriptorInfo = sortDescriptors.map { ($0.key ?? "", $0.ascending) }
        
        return try bgContext.performAndWait {
            let request: NSFetchRequest<CDTrack> = CDTrack.fetchRequest()
            // Recreate predicate from format string inside the closure
            request.predicate = NSPredicate(format: predicateFormat)
            // Recreate sort descriptors inside the closure
            request.sortDescriptors = sortDescriptorInfo.map { key, ascending in
                NSSortDescriptor(key: key, ascending: ascending)
            }
            return try bgContext.fetch(request)
        }
    }
    
    /// Find track by ID
    func findTrack(id: String, serverId: UUID) throws -> CDTrack? {
        return try bgContext.performAndWait {
            let serverRequest: NSFetchRequest<CDServer> = CDServer.fetchRequest()
            serverRequest.predicate = NSPredicate(format: "id == %@", serverId as CVarArg)
            serverRequest.fetchLimit = 1
            
            guard let server = try bgContext.fetch(serverRequest).first else {
                return nil
            }
            
            return try CDTrack.findBy(id: id, server: server, in: bgContext)
        }
    }
    
    // MARK: - Context Management
    
    /// Get a background context for complex operations
    /// Note: This context should only be used within the actor's methods
    var backgroundContext: NSManagedObjectContext {
        return bgContext
    }
    
    /// Save the background context
    func save() throws {
        try bgContext.performAndWait {
            if bgContext.hasChanges {
                try bgContext.save()
            }
        }
    }
    
    /// Perform an operation on the background context
    func perform<T>(_ block: @escaping (NSManagedObjectContext) throws -> T) async throws -> T {
        return try await bgContext.perform {
            try block(self.bgContext)
        }
    }
}

