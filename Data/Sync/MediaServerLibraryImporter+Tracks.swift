
import Foundation
@preconcurrency import CoreData

enum TrackSyncPhase {
    static func upsertTracks(
        from trackDTOs: [JellyfinTrackDTO],
        albums: [String: CDAlbum],
        artists: [String: CDArtist],
        genres: [String: CDGenre],
        existingTracks: [String: CDTrack],
        server: CDServer,
        in context: NSManagedObjectContext,
        progressCallback: @Sendable @escaping (SyncProgress) -> Void,
        logger: AppLogger
    ) {
        var seenTrackIds = Set<String>()
        let uniqueTrackDTOs = trackDTOs.filter { dto in
            if seenTrackIds.contains(dto.id) {
                logger.warning("Skipping duplicate track ID: \(dto.id) (\(dto.name))")
                return false
            }
            seenTrackIds.insert(dto.id)
            return true
        }
        
        logger.info("Processing \(uniqueTrackDTOs.count) unique tracks (filtered \(trackDTOs.count - uniqueTrackDTOs.count) duplicates)")
        
        DispatchQueue.main.async {
            progressCallback(SyncProgress(progress: 0.75, stage: "Processing library..."))
        }
        
        var existingTrackMap = existingTracks
        let newTrackDTOs = uniqueTrackDTOs.filter { dto in
            existingTrackMap[dto.id] == nil
        }
        logger.debug("Creating \(newTrackDTOs.count) new tracks in bulk")
        
        for dto in newTrackDTOs {
            let newTrack = CDTrack(context: context)
            newTrack.id = dto.id
            newTrack.server = server
            existingTrackMap[dto.id] = newTrack
        }
        logger.debug("Created \(newTrackDTOs.count) new CDTrack objects")
        
        var favoriteMap: [String: Bool] = [:]
        for dto in uniqueTrackDTOs {
            favoriteMap[dto.id] = dto.userData?.isFavorite ?? false
        }
        
        var tracksNeedingLikeUpdate: [CDTrack] = []
        for (trackId, cdTrack) in existingTrackMap {
            if let serverIsLiked = favoriteMap[trackId],
               cdTrack.isLiked != serverIsLiked {
                tracksNeedingLikeUpdate.append(cdTrack)
            }
        }
        logger.debug("Found \(tracksNeedingLikeUpdate.count) tracks needing isLiked update")
        
        let totalTracks = uniqueTrackDTOs.count
        for (index, dto) in uniqueTrackDTOs.enumerated() {
            if index % 500 == 0 || index == totalTracks - 1 {
                let progress = 0.75 + (Double(index + 1) / Double(totalTracks)) * 0.20
                DispatchQueue.main.async {
                    progressCallback(SyncProgress(progress: progress, stage: "Processing library..."))
                }
            }
            
            let album = dto.albumId.flatMap { albums[$0] }
            
            let artist = dto.artists?.first.flatMap { artistName in
                artists.values.first { $0.name == artistName }
            } ?? album?.artist
            
            let splitGenres = UmbrellaGenres.splitGenres(dto.genres ?? [])
            var trackGenres = Set(splitGenres.compactMap { genreName in
                genres[UmbrellaGenres.normalize(genreName)]
            })
            if trackGenres.isEmpty {
                let unknownNormalized = UmbrellaGenres.normalize("Unknown")
                if let unknownGenre = genres[unknownNormalized] {
                    trackGenres.insert(unknownGenre)
                }
            }
            
            let cdTrack = existingTrackMap[dto.id]!
            
            if index < 5 || index >= totalTracks - 5 {
                let wasNew = newTrackDTOs.contains { $0.id == dto.id }
                if wasNew {
                    logger.debug("Processing NEW track - ID: \(dto.id), Title: \(dto.name)")
                } else {
                    logger.debug("Processing EXISTING track - ID: \(dto.id), Title: \(dto.name)")
                }
            }
            
            cdTrack.id = dto.id
            cdTrack.title = dto.name
            cdTrack.duration = {
                let ticks = dto.runTimeTicks ?? 0
                if ticks > 0 {
                    let calculated = TimeInterval(ticks) / 10_000_000.0
                    if calculated.isNaN || calculated.isInfinite {
                        return 0
                    }
                    return calculated
                }
                return 0
            }()
            cdTrack.trackNumber = Int16(dto.indexNumber ?? 0)
            cdTrack.discNumber = Int16(dto.discNumber ?? 0)
            
            let newIsLiked = dto.userData?.isFavorite ?? false
            cdTrack.isLiked = newIsLiked
            
            cdTrack.playCount = Int32(dto.playCount ?? 0)
            cdTrack.container = dto.container
            
            if let dateString = dto.dateAdded, !dateString.isEmpty {
                let formatter = ISO8601DateFormatter()
                formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                var date = formatter.date(from: dateString)
                if date == nil {
                    formatter.formatOptions = [.withInternetDateTime]
                    date = formatter.date(from: dateString)
                }
                cdTrack.dateAdded = date
            }
            
            let genreNames = dto.genres ?? []
            let classification = UmbrellaGenres.classifyGenres(genreNames)
            let rawGenres = classification.raw.isEmpty ? [] : classification.raw
            let normalizedGenres = classification.normalized.isEmpty ? [] : classification.normalized
            let umbrellaGenres = classification.umbrella.isEmpty ? ["Unknown"] : classification.umbrella
            cdTrack.rawGenres = rawGenres as NSArray
            cdTrack.normalizedGenres = normalizedGenres as NSArray
            cdTrack.umbrellaGenres = umbrellaGenres as NSArray
            
            cdTrack.album = album
            cdTrack.artist = artist
            cdTrack.genres = NSSet(set: trackGenres)
            cdTrack.server = server
        }
        
        DispatchQueue.main.async {
            progressCallback(SyncProgress(progress: 0.93, stage: "Processing library..."))
        }
        
        for cdTrack in tracksNeedingLikeUpdate {
            if let trackId = cdTrack.id, let serverIsLiked = favoriteMap[trackId] {
                cdTrack.isLiked = serverIsLiked
            }
        }
        if !tracksNeedingLikeUpdate.isEmpty {
            logger.debug("Bulk updated isLiked for \(tracksNeedingLikeUpdate.count) tracks")
        }
        
        DispatchQueue.main.async {
            progressCallback(SyncProgress(progress: 0.95, stage: "Processing library..."))
        }
    }
}
