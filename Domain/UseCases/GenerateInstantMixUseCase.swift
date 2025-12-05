
import Foundation

struct GenerateInstantMixUseCase {
    let playbackRepository: PlaybackRepository

    func execute(from itemId: String, kind: InstantMixKind) async throws -> [Track] {
        try await playbackRepository.generateInstantMix(from: itemId, kind: kind, serverId: nil)
    }
}

