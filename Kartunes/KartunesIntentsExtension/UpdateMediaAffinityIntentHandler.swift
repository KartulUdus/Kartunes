import Intents
import Foundation

/// Handles INUpdateMediaAffinityIntent requests from Siri (like/unlike tracks)
final class UpdateMediaAffinityIntentHandler: NSObject, INUpdateMediaAffinityIntentHandling {
    
    // MARK: - INUpdateMediaAffinityIntentHandling
    
    /// Resolve which media item to like/unlike
    func resolveMediaItems(for intent: INUpdateMediaAffinityIntent, with completion: @escaping ([INUpdateMediaAffinityMediaItemResolutionResult]) -> Void) {
        // If Siri provided explicit media items, use those
        if let items = intent.mediaItems, !items.isEmpty {
            let results = items.map { INUpdateMediaAffinityMediaItemResolutionResult.success(with: $0) }
            completion(results)
            return
        }
        
        // Fallback: use currently playing track from shared app state
        if let currentTrack = SharedPlaybackState.loadCurrentTrackAsINMediaItem() {
            completion([.success(with: currentTrack)])
        } else {
            // No current track available
            completion([.unsupported()])
        }
    }
    
    /// Resolve the affinity type (like or dislike)
    func resolveAffinityType(for intent: INUpdateMediaAffinityIntent, with completion: @escaping (INMediaAffinityTypeResolutionResult) -> Void) {
        // Use the affinity type from the intent (like or dislike)
        completion(.success(with: intent.affinityType))
    }
    
    /// Handle the like/unlike request
    func handle(intent: INUpdateMediaAffinityIntent, completion: @escaping (INUpdateMediaAffinityIntentResponse) -> Void) {
        guard let item = intent.mediaItems?.first,
              let trackId = item.identifier else {
            // No track specified
            let response = INUpdateMediaAffinityIntentResponse(code: .failure, userActivity: nil)
            completion(response)
            return
        }
        
        // Determine if this is a like or dislike
        let isLike = intent.affinityType == .like
        
        // Write the request to App Group for the main app to handle
        SharedPlaybackState.requestLikeChange(trackId: trackId, isLike: isLike)
        
        // Return success - the app will handle the actual like/unlike when it launches
        // The request is saved to App Group, so the app can process it on activation
        let response = INUpdateMediaAffinityIntentResponse(code: .success, userActivity: nil)
        completion(response)
    }
}

