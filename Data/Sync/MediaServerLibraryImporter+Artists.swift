
import Foundation
@preconcurrency import CoreData

enum ArtistSyncPhase {
    static func upsertArtists(
        from artistDTOs: [JellyfinArtistDTO],
        in context: NSManagedObjectContext,
        server: CDServer,
        apiClient: MediaServerAPIClient,
        existing: [String: CDArtist],
        progressCallback: @Sendable @escaping (SyncProgress) -> Void
    ) -> [String: CDArtist] {
        DispatchQueue.main.async {
            progressCallback(SyncProgress(progress: 0.52, stage: "Processing library..."))
        }
        
        var artistMap: [String: CDArtist] = [:]
        let totalArtists = artistDTOs.count
        for (index, dto) in artistDTOs.enumerated() {
            if index % 100 == 0 || index == totalArtists - 1 {
                let progress = 0.52 + (Double(index + 1) / Double(totalArtists)) * 0.08
                DispatchQueue.main.async {
                    progressCallback(SyncProgress(progress: progress, stage: "Processing library..."))
                }
            }
            
            let cdArtist = existing[dto.id] ?? CDArtist(context: context)
            
            cdArtist.id = dto.id
            cdArtist.name = dto.name
            cdArtist.sortName = dto.name
            cdArtist.imageTagPrimary = dto.imageTags?["Primary"]
            
            if let imageTag = dto.imageTags?["Primary"], !imageTag.isEmpty {
                if let embyClient = apiClient as? DefaultEmbyAPIClient {
                    cdArtist.imageURL = embyClient.buildImageURL(forItemId: dto.id, imageType: "Primary", maxWidth: 300, tag: imageTag)?.absoluteString
                } else {
                    cdArtist.imageURL = apiClient.buildImageURL(forItemId: dto.id, imageType: "Primary", maxWidth: 300)?.absoluteString
                }
            } else {
                cdArtist.imageURL = apiClient.buildImageURL(forItemId: dto.id, imageType: "Primary", maxWidth: 300)?.absoluteString
            }
            
            cdArtist.server = server
            
            artistMap[dto.id] = cdArtist
        }
        
        DispatchQueue.main.async {
            progressCallback(SyncProgress(progress: 0.60, stage: "Processing library..."))
        }
        
        return artistMap
    }
}
