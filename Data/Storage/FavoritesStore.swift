
import Foundation
@preconcurrency import CoreData

/// Centralized store for managing liked/favorite track state
/// Prevents race conditions and ensures single source of truth
/// Uses LibraryStore actor for thread-safe Core Data access
@MainActor
final class FavoritesStore {
    static let shared = FavoritesStore()
    
    private var likedTrackIds: Set<String> = []
    private let logger = Log.make(.storage)
    private let libraryStore: LibraryStore
    
    private init() {
        self.libraryStore = LibraryStore(container: CoreDataStack.shared.persistentContainer)
        Task {
            await loadLikedTracks()
        }
    }
    
    /// Check if a track is liked
    func isLiked(_ trackId: String) -> Bool {
        return likedTrackIds.contains(trackId)
    }
    
    /// Set the liked state for a track (in-memory only, use updateAfterAPICall for persistence)
    func setLiked(_ trackId: String, _ liked: Bool) {
        if liked {
            likedTrackIds.insert(trackId)
        } else {
            likedTrackIds.remove(trackId)
        }
    }
    
    /// Toggle the liked state for a track
    func toggleLiked(_ trackId: String) -> Bool {
        let newValue = !isLiked(trackId)
        setLiked(trackId, newValue)
        return newValue
    }
    
    /// Load liked tracks from Core Data via LibraryStore actor
    private func loadLikedTracks() async {
        do {
            let trackIds = try await libraryStore.fetchLikedTrackIds()
            await MainActor.run {
                self.likedTrackIds = trackIds
                self.logger.debug("FavoritesStore: Loaded \(trackIds.count) liked tracks")
            }
        } catch {
            await MainActor.run {
                self.logger.error("FavoritesStore: Failed to load liked tracks: \(error.localizedDescription)")
            }
        }
    }
    
    /// Refresh liked tracks from Core Data (call after external changes)
    func refresh() {
        Task {
            await loadLikedTracks()
        }
    }
    
    /// Update liked state after a successful API call
    /// This persists to Core Data via LibraryStore
    func updateAfterAPICall(trackId: String, isLiked: Bool, serverId: UUID) {
        // Update in-memory state immediately
        setLiked(trackId, isLiked)
        
        // Persist to Core Data via LibraryStore actor
        Task {
            do {
                try await libraryStore.updateLikedStatus(trackId: trackId, isLiked: isLiked, serverId: serverId)
            } catch {
                await MainActor.run {
                    self.logger.error("FavoritesStore: Failed to persist liked status: \(error.localizedDescription)")
                }
            }
        }
    }
}

