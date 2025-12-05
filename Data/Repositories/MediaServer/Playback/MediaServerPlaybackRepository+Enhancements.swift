
import Foundation
import AVFoundation
@preconcurrency import CoreData

extension MediaServerPlaybackRepository {
    func getCurrentTime() async -> TimeInterval {
        guard let player = player,
              let currentItem = player.currentItem,
              currentItem.status == .readyToPlay else { return 0 }
        
        // Check if timebase is valid before accessing currentTime
        // We can get time even when paused (rate == 0)
        let currentTime = player.currentTime()
        guard CMTIME_IS_VALID(currentTime) && !CMTIME_IS_INDEFINITE(currentTime) else {
            return 0
        }
        
        return currentTime.seconds
    }
    
    func getDuration() async -> TimeInterval? {
        guard let currentItem = player?.currentItem,
              currentItem.status == .readyToPlay else { return nil }
        
        do {
            let duration = try await currentItem.asset.load(.duration)
            guard CMTIME_IS_VALID(duration) && !CMTIME_IS_INDEFINITE(duration) else {
                return nil
            }
            return duration.seconds
        } catch {
            return nil
        }
    }
    
    func getCurrentTrack() async -> Track? {
        guard currentIndex < currentQueue.count else { return nil }
        return currentQueue[currentIndex]
    }
    
    func getQueue() async -> [Track] {
        return currentQueue
    }
    
    func toggleLike(track: Track) async throws -> Track {
        let newLikedState = !track.isLiked
        
        // Call the backend API
        try await apiClient.toggleFavorite(itemId: track.id, isFavorite: newLikedState)
        
        // Update CoreData
        let context = coreDataStack.newBackgroundContext()
        try await context.perform {
            // Find the server
            let serverRequest: NSFetchRequest<CDServer> = CDServer.fetchRequest()
            serverRequest.predicate = NSPredicate(format: "id == %@", track.serverId as CVarArg)
            serverRequest.fetchLimit = 1
            
            guard let server = try context.fetch(serverRequest).first else {
                self.logger.warning("Playback: track not found in Core Data during toggleLike")
                return
            }
            
            // Find the track in CoreData
            if let cdTrack = try? CDTrack.findBy(id: track.id, server: server, in: context) {
                cdTrack.isLiked = newLikedState
                do {
                    try context.save()
                } catch {
                    self.logger.error("Playback: failed to save Core Data context after updating liked status: \(error)")
                    throw error
                }
            } else {
                self.logger.warning("Playback: track not found in CoreData, skipping update")
            }
        }
        
        // Update the track in the current queue if it exists
        if let queueIndex = currentQueue.firstIndex(where: { $0.id == track.id }) {
            currentQueue[queueIndex] = Track(
                id: track.id,
                title: track.title,
                albumId: track.albumId,
                albumTitle: track.albumTitle,
                artistName: track.artistName,
                duration: track.duration,
                trackNumber: track.trackNumber,
                discNumber: track.discNumber,
                dateAdded: track.dateAdded,
                playCount: track.playCount,
                isLiked: newLikedState,
                streamUrl: track.streamUrl,
                serverId: track.serverId
            )
        }
        
        return Track(
            id: track.id,
            title: track.title,
            albumId: track.albumId,
            albumTitle: track.albumTitle,
            artistName: track.artistName,
            duration: track.duration,
            trackNumber: track.trackNumber,
            discNumber: track.discNumber,
            dateAdded: track.dateAdded,
            playCount: track.playCount,
            isLiked: newLikedState,
            streamUrl: track.streamUrl,
            serverId: track.serverId
        )
    }
    
    func generateInstantMix(from itemId: String, kind: InstantMixKind, serverId: UUID?) async throws -> [Track] {
        let dtos = try await apiClient.fetchInstantMix(fromItemId: itemId, type: kind)
        logger.info("Playback: instant mix generated: \(dtos.count) tracks")
        
        // Get serverId from parameter, current track/queue, or CoreData lookup
        let resolvedServerId: UUID
        if let providedServerId = serverId {
            resolvedServerId = providedServerId
        } else if let queueServerId = currentQueue.first?.serverId {
            resolvedServerId = queueServerId
        } else if let currentTrack = await getCurrentTrack() {
            resolvedServerId = currentTrack.serverId
        } else {
            // Try to find serverId from CoreData by looking up the item
            let context = coreDataStack.viewContext
            if let cdAlbum = try? await context.perform({
                let request: NSFetchRequest<CDAlbum> = CDAlbum.fetchRequest()
                request.predicate = NSPredicate(format: "id == %@", itemId)
                request.fetchLimit = 1
                return try context.fetch(request).first
            }), let serverId = cdAlbum.server?.id {
                resolvedServerId = serverId
            } else if let cdArtist = try? await context.perform({
                let request: NSFetchRequest<CDArtist> = CDArtist.fetchRequest()
                request.predicate = NSPredicate(format: "id == %@", itemId)
                request.fetchLimit = 1
                return try context.fetch(request).first
            }), let serverId = cdArtist.server?.id {
                resolvedServerId = serverId
            } else {
                throw NSError(domain: "MediaServerPlaybackRepository", code: -1, userInfo: [NSLocalizedDescriptionKey: "Cannot determine serverId for instant mix"])
            }
        }
        
        // Convert DTOs to Track entities using shared mapping
        return dtos.map { dto in
            Track(
                dto: dto,
                serverId: resolvedServerId,
                apiClient: apiClient,
                isLiked: nil // Use DTO's userData.isFavorite
            )
        }
    }
}

