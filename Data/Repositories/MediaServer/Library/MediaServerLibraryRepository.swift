
import Foundation
@preconcurrency import CoreData

final class MediaServerLibraryRepository: LibraryRepository {
    let apiClient: MediaServerAPIClient
    let coreDataStack: CoreDataStack
    let serverId: UUID
    let logger: AppLogger
    
    init(apiClient: MediaServerAPIClient, serverId: UUID, coreDataStack: CoreDataStack = .shared, logger: AppLogger = Log.make(.networking)) {
        self.apiClient = apiClient
        self.serverId = serverId
        self.coreDataStack = coreDataStack
        self.logger = logger
    }
}

enum LibraryRepositoryError: Error {
    case serverNotFound
    case invalidAlbumId
    case invalidPlaylistId
    
    var localizedDescription: String {
        switch self {
        case .serverNotFound:
            return "Server not found"
        case .invalidAlbumId:
            return "Invalid album ID"
        case .invalidPlaylistId:
            return "Invalid playlist ID"
        }
    }
}

