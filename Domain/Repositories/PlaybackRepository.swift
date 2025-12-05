
import Foundation

protocol PlaybackRepository {
    func play(track: Track) async
    func play(queue: [Track], startingAt index: Int) async
    func pause() async
    func resume() async
    func stop() async
    func next() async
    func previous() async
    func skipTo(index: Int) async
    func seek(to time: TimeInterval) async
    func getCurrentTime() async -> TimeInterval
    func getDuration() async -> TimeInterval?
    func getCurrentTrack() async -> Track?
    func getQueue() async -> [Track]
    func toggleLike(track: Track) async throws -> Track
    func generateInstantMix(from itemId: String, kind: InstantMixKind, serverId: UUID?) async throws -> [Track]
}

