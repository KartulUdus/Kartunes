
import Foundation

struct ShuffleByArtistUseCase {
    let libraryRepository: LibraryRepository
    let playbackRepository: PlaybackRepository

    func execute(artistId: String) async throws {
        let tracks = try await libraryRepository.fetchTracks(albumId: nil)
        let filteredTracks = tracks.filter { $0.artistName == artistId }
        let shuffled = filteredTracks.shuffled()
        if let firstIdx = shuffled.indices.first {
            await playbackRepository.play(queue: shuffled, startingAt: firstIdx)
        }
    }
}

