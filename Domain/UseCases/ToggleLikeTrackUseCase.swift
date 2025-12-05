
import Foundation

struct ToggleLikeTrackUseCase {
    let playbackRepository: PlaybackRepository

    func execute(track: Track) async throws -> Track {
        try await playbackRepository.toggleLike(track: track)
    }
}

