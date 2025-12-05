
import Foundation
@preconcurrency import CoreData

extension MediaServerPlaybackRepository {
    func handleTrackNotFound(trackId: String) async {
        logger.warning("Playback: track not found (404), id=\(trackId)")
        
        // Delete track from CoreData using helper
        let context = coreDataStack.viewContext
        await context.perform {
            do {
                // Get track title for logging before deletion
                let request: NSFetchRequest<CDTrack> = CDTrack.fetchRequest()
                request.predicate = NSPredicate(format: "id == %@", trackId)
                request.fetchLimit = 1
                let trackTitle = (try? context.fetch(request).first)?.title ?? "Unknown"
                
                // Delete using helper
                try CDTrack.deleteById(trackId, in: context)
                self.logger.debug("Playback: deleted track from CoreData: \(trackTitle)")
            } catch {
                self.logger.error("Playback: failed to delete track from Core Data: \(error)")
            }
        }
        
        // Notify via callback
        await onTrackNotFound?(trackId)
    }
}

