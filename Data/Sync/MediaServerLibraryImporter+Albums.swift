
import Foundation
@preconcurrency import CoreData

enum AlbumSyncPhase {
    static func upsertAlbums(
        from albumDTOs: [JellyfinAlbumDTO],
        artists: [String: CDArtist],
        in context: NSManagedObjectContext,
        server: CDServer,
        apiClient: MediaServerAPIClient,
        existing: [String: CDAlbum],
        progressCallback: @Sendable @escaping (SyncProgress) -> Void,
        logger: AppLogger
    ) -> [String: CDAlbum] {
        var albumMap: [String: CDAlbum] = [:]
        let totalAlbums = albumDTOs.count
        for (index, dto) in albumDTOs.enumerated() {
            if index % 100 == 0 || index == totalAlbums - 1 {
                let progress = 0.60 + (Double(index + 1) / Double(totalAlbums)) * 0.10
                DispatchQueue.main.async {
                    progressCallback(SyncProgress(progress: progress, stage: "Processing library..."))
                }
            }
            
            let artist = dto.artistName.flatMap { artistName in
                artists.values.first { $0.name == artistName || $0.name?.caseInsensitiveCompare(artistName) == .orderedSame }
            }
            
            let cdAlbum = existing[dto.id] ?? CDAlbum(context: context)
            
            if let tags = dto.imageTags {
                logger.debug("Album '\(dto.name)' (ID: \(dto.id)) ImageTags: \(tags)")
            } else {
                logger.warning("Album '\(dto.name)' (ID: \(dto.id)) has no ImageTags")
            }
            
            cdAlbum.id = dto.id
            cdAlbum.title = dto.name
            cdAlbum.sortTitle = dto.name
            cdAlbum.year = Int16(dto.productionYear ?? 0)
            
            var imageTag: String? = dto.imageTags?["Primary"] ?? dto.imageTags?["primary"]
            var imageType = "Primary"
            
            if imageTag == nil || imageTag!.isEmpty {
                imageTag = dto.imageTags?["Thumb"] ?? dto.imageTags?["thumb"]
                if imageTag != nil && !imageTag!.isEmpty {
                    imageType = "Thumb"
                } else {
                    imageTag = dto.imageTags?.values.first
                    if imageTag != nil && !imageTag!.isEmpty {
                        imageType = dto.imageTags?.keys.first ?? "Primary"
                    }
                }
            }
            
            cdAlbum.imageTagPrimary = imageTag
            cdAlbum.isFavorite = false
            
            if let tag = imageTag, !tag.isEmpty {
                if let embyClient = apiClient as? DefaultEmbyAPIClient {
                    cdAlbum.imageURL = embyClient.buildImageURL(forItemId: dto.id, imageType: imageType, maxWidth: 300, tag: tag)?.absoluteString
                    logger.debug("Built image URL for album '\(dto.name)' (ID: \(dto.id)) with tag: \(tag), type: \(imageType), URL: \(cdAlbum.imageURL ?? "nil")")
                } else {
                    cdAlbum.imageURL = apiClient.buildImageURL(forItemId: dto.id, imageType: imageType, maxWidth: 300)?.absoluteString
                }
            } else {
                if let embyClient = apiClient as? DefaultEmbyAPIClient {
                    cdAlbum.imageURL = embyClient.buildImageURL(forItemId: dto.id, imageType: "Primary", maxWidth: 300, tag: nil)?.absoluteString
                    logger.debug("Built image URL for album '\(dto.name)' (ID: \(dto.id)) without tag (Emby), trying Primary, URL: \(cdAlbum.imageURL ?? "nil")")
                } else {
                    cdAlbum.imageURL = apiClient.buildImageURL(forItemId: dto.id, imageType: "Primary", maxWidth: 300)?.absoluteString
                    logger.debug("Built image URL for album '\(dto.name)' (ID: \(dto.id)) without tag, URL: \(cdAlbum.imageURL ?? "nil")")
                }
            }
            
            cdAlbum.artist = artist
            cdAlbum.server = server
            
            albumMap[dto.id] = cdAlbum
        }
        
        DispatchQueue.main.async {
            progressCallback(SyncProgress(progress: 0.70, stage: "Processing library..."))
        }
        
        return albumMap
    }
}
