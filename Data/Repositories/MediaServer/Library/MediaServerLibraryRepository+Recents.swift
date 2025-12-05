
import Foundation
@preconcurrency import CoreData

extension MediaServerLibraryRepository {
    func fetchRecentlyPlayed(limit: Int = 50) async throws -> [Track] {
        // Fetch from API
        let dtos = try await apiClient.fetchRecentlyPlayed(limit: limit)
        
        // Sync missing metadata to CoreData
        try await syncMissingMetadata(for: dtos)
        
        // Convert DTOs to Track entities
        return dtos.map { dto in
            Track(dto: dto, serverId: serverId, apiClient: apiClient)
        }
    }
    
    func fetchRecentlyAdded(limit: Int = 500) async throws -> [Track] {
        // Fetch from API
        let dtos = try await apiClient.fetchRecentlyAdded(limit: limit)
        
        // Sync missing metadata to CoreData
        try await syncMissingMetadata(for: dtos)
        
        // Convert DTOs to Track entities
        return dtos.map { dto in
            Track(dto: dto, serverId: serverId, apiClient: apiClient)
        }
    }
}

