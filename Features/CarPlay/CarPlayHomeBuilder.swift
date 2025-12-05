
import CarPlay
import Combine

@MainActor
final class CarPlayHomeBuilder {
    private let logger = Log.make(.carPlay)
    
    private let playbackViewModel: PlaybackViewModel
    private let libraryRepository: LibraryRepository
    private let playbackRepository: PlaybackRepository
    private weak var interfaceController: CPInterfaceController?
    private var cancellables = Set<AnyCancellable>()
    
    init(
        playbackViewModel: PlaybackViewModel,
        libraryRepository: LibraryRepository,
        playbackRepository: PlaybackRepository,
        interfaceController: CPInterfaceController
    ) {
        self.playbackViewModel = playbackViewModel
        self.libraryRepository = libraryRepository
        self.playbackRepository = playbackRepository
        self.interfaceController = interfaceController
    }
    
    func updateRepositories(
        playbackViewModel: PlaybackViewModel,
        libraryRepository: LibraryRepository,
        playbackRepository: PlaybackRepository
    ) {
        self.playbackViewModel = playbackViewModel
        self.libraryRepository = libraryRepository
        self.playbackRepository = playbackRepository
    }
    
    func buildHomeTemplate() -> CPListTemplate {
        var sections: [CPListSection] = []
        
        // Section 1: Resume Listening
        if let resumeSection = buildResumeSection() {
            sections.append(resumeSection)
        }
        
        // Section 2: Random by Genre (stub for Phase 1)
        let genreSection = buildGenreSection()
        sections.append(genreSection)
        
        return CPListTemplate(title: "Home", sections: sections)
    }
    
    private func buildResumeSection() -> CPListSection? {
        // Check if there's a current queue
        guard let currentTrack = playbackViewModel.currentTrack,
              !playbackViewModel.queue.isEmpty else {
            return nil
        }
        
        let item = CPListItem(
            text: "Continue Playing",
            detailText: "\(currentTrack.title) - \(currentTrack.artistName)"
        )
        
        item.handler = { [weak self] _, completion in
            Task { @MainActor [weak self] in
                guard let self = self else {
                    completion(false)
                    return
                }
                
                // Resume playback if paused
                if !self.playbackViewModel.isPlaying {
                    await self.playbackRepository.resume()
                    self.playbackViewModel.isPlaying = true
                }
                
                // Show Now Playing
                self.interfaceController?.pushTemplate(
                    CPNowPlayingTemplate.shared,
                    animated: true
                ) { _, _ in }
                
                completion(true)
            }
        }
        
        return CPListSection(items: [item], header: "Resume Listening", headerSubtitle: nil)
    }
    
    private func buildGenreSection() -> CPListSection {
        // Phase 1: Stub genres
        // TODO: Fetch actual genres from library
        let genres = ["Rock", "Pop", "Jazz", "Electronic", "Classical"]
        
        let items = genres.map { genreName -> CPListItem in
            let item = CPListItem(text: genreName, detailText: "Play random songs")
            
            item.handler = { [weak self] _, completion in
                Task { @MainActor [weak self] in
                    guard let self = self else {
                        completion(false)
                        return
                    }
                    
                    // TODO: Implement "play random from genre" logic
                    // For Phase 1, this is a stub
                    self.logger.debug("Play random from genre \(genreName)")
                    completion(false) // Not implemented yet
                }
            }
            
            return item
        }
        
        return CPListSection(items: items, header: "Random by Genre", headerSubtitle: nil)
    }
}

