
import Foundation
@preconcurrency import CoreData

enum GenreSyncPhase {
    static func upsertGenres(
        from trackDTOs: [JellyfinTrackDTO],
        existing: [String: CDGenre],
        server: CDServer,
        in context: NSManagedObjectContext
    ) -> [String: CDGenre] {
        var genreMap: [String: CDGenre] = [:]
        
        let allGenreNames = Set(trackDTOs.flatMap { dto in
            UmbrellaGenres.splitGenres(dto.genres ?? [])
        })
        
        for genreName in allGenreNames {
            let normalized = UmbrellaGenres.normalize(genreName)
            if genreMap[normalized] == nil {
                let cdGenre = existing[normalized] ?? CDGenre(context: context)
                
                cdGenre.rawName = genreName
                cdGenre.normalizedName = normalized
                cdGenre.umbrellaName = UmbrellaGenres.resolve(genreName)
                cdGenre.server = server
                
                genreMap[normalized] = cdGenre
            }
        }
        
        let unknownNormalized = UmbrellaGenres.normalize("Unknown")
        if genreMap[unknownNormalized] == nil {
            let unknownGenre = existing[unknownNormalized] ?? CDGenre(context: context)
            unknownGenre.rawName = "Unknown"
            unknownGenre.normalizedName = unknownNormalized
            unknownGenre.umbrellaName = "Unknown"
            unknownGenre.server = server
            genreMap[unknownNormalized] = unknownGenre
        }
        
        return genreMap
    }
}


