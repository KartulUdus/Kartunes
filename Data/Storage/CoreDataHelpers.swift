
import Foundation
import CoreData

// MARK: - Server Helpers

struct CoreDataServerHelper {
    static func toDomain(_ cdServer: CDServer) -> Server {
        let serverType: MediaServerType
        if let typeRaw = cdServer.typeRaw, let type = MediaServerType(rawValue: typeRaw) {
            serverType = type
        } else {
            serverType = .jellyfin
        }
        
        return Server(
            id: cdServer.id ?? UUID(),
            name: cdServer.name ?? "",
            baseURL: URL(string: cdServer.baseURL ?? "") ?? URL(string: "https://example.com")!,
            username: cdServer.username ?? "",
            userId: cdServer.userId ?? "",
            accessToken: cdServer.accessToken ?? "",
            serverType: serverType
        )
    }
    
    static func fromDomain(_ server: Server, in context: NSManagedObjectContext) -> CDServer {
        let cdServer = CDServer(context: context)
        cdServer.id = server.id
        cdServer.name = server.name
        cdServer.baseURL = server.baseURL.absoluteString
        cdServer.username = server.username
        cdServer.userId = server.userId
        cdServer.accessToken = server.accessToken
        cdServer.serverType = server.serverType
        cdServer.isActive = false // Will be set separately
        return cdServer
    }
    
    static func fetchActive(in context: NSManagedObjectContext) throws -> CDServer? {
        let request: NSFetchRequest<CDServer> = CDServer.fetchRequest()
        request.predicate = NSPredicate(format: "isActive == YES")
        request.fetchLimit = 1
        return try context.fetch(request).first
    }
    
    static func fetchAll(in context: NSManagedObjectContext) throws -> [CDServer] {
        let request: NSFetchRequest<CDServer> = CDServer.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(key: "name", ascending: true)]
        return try context.fetch(request)
    }
    
    static func findBy(id: UUID, in context: NSManagedObjectContext) throws -> CDServer? {
        let request: NSFetchRequest<CDServer> = CDServer.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        request.fetchLimit = 1
        return try context.fetch(request).first
    }
}

// MARK: - Track Helpers

struct CoreDataTrackHelper {
    private static let logger = Log.make(.storage)
    static func toDomain(_ cdTrack: CDTrack, serverId: UUID) -> Track {
        // Map from relationships to flat structure for UI compatibility
        Track(
            id: cdTrack.id ?? "",
            title: cdTrack.title ?? "",
            albumId: cdTrack.album?.id,
            albumTitle: cdTrack.album?.title,
            artistName: cdTrack.artist?.name ?? "Unknown Artist",
            duration: cdTrack.duration,
            trackNumber: cdTrack.trackNumber > 0 ? Int(cdTrack.trackNumber) : nil,
            discNumber: cdTrack.discNumber > 0 ? Int(cdTrack.discNumber) : nil,
            dateAdded: cdTrack.dateAdded,
            playCount: Int(cdTrack.playCount),
            isLiked: cdTrack.isLiked,
            streamUrl: nil, // Will be built when needed
            serverId: serverId
        )
    }
    
    static func findBy(id: String, server: CDServer, in context: NSManagedObjectContext) throws -> CDTrack? {
        let request: NSFetchRequest<CDTrack> = CDTrack.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@ AND server == %@", id, server)
        request.fetchLimit = 1
        let result = try context.fetch(request).first
        if let track = result {
            Self.logger.debug("CoreDataTrackHelper.findBy - Track EXISTS - ID: \(id), Title: \(track.title ?? "Unknown")")
        } else {
            Self.logger.debug("CoreDataTrackHelper.findBy - Track DOES NOT EXIST - ID: \(id)")
        }
        return result
    }
    
    static func fetchAll(server: CDServer, in context: NSManagedObjectContext) throws -> [CDTrack] {
        let request: NSFetchRequest<CDTrack> = CDTrack.fetchRequest()
        request.predicate = NSPredicate(format: "server == %@", server)
        request.sortDescriptors = [NSSortDescriptor(key: "title", ascending: true)]
        return try context.fetch(request)
    }
    
    static func fetchByAlbum(_ album: CDAlbum, in context: NSManagedObjectContext) throws -> [CDTrack] {
        let request: NSFetchRequest<CDTrack> = CDTrack.fetchRequest()
        request.predicate = NSPredicate(format: "album == %@", album)
        request.sortDescriptors = [
            NSSortDescriptor(key: "discNumber", ascending: true),
            NSSortDescriptor(key: "trackNumber", ascending: true)
        ]
        return try context.fetch(request)
    }
}
