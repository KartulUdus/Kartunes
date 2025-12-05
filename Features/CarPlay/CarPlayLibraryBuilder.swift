
import CarPlay

@MainActor
final class CarPlayLibraryBuilder {
    private let logger = Log.make(.carPlay)
    
    private let libraryRepository: LibraryRepository
    private let playbackRepository: PlaybackRepository
    private let playbackViewModel: PlaybackViewModel
    private weak var interfaceController: CPInterfaceController?
    
    init(
        libraryRepository: LibraryRepository,
        playbackRepository: PlaybackRepository,
        playbackViewModel: PlaybackViewModel,
        interfaceController: CPInterfaceController
    ) {
        self.libraryRepository = libraryRepository
        self.playbackRepository = playbackRepository
        self.playbackViewModel = playbackViewModel
        self.interfaceController = interfaceController
    }
    
    func updateRepositories(
        libraryRepository: LibraryRepository,
        playbackRepository: PlaybackRepository,
        playbackViewModel: PlaybackViewModel
    ) {
        self.libraryRepository = libraryRepository
        self.playbackRepository = playbackRepository
        self.playbackViewModel = playbackViewModel
    }
    
    func buildLibraryRootTemplate() -> CPListTemplate {
        let items = [
            buildPlaylistsItem(),
            buildGenresItem(),
            buildArtistsItem(),
            buildAlbumsItem(),
            buildSongsItem()
        ]
        
        let section = CPListSection(items: items, header: nil, headerSubtitle: nil)
        return CPListTemplate(title: "Library", sections: [section])
    }
    
    // MARK: - Library Items
    
    private func buildPlaylistsItem() -> CPListItem {
        let item = CPListItem(text: "Playlists", detailText: nil)
        
        item.handler = { [weak self] _, completion in
            Task { @MainActor [weak self] in
                guard let self = self else {
                    completion(false)
                    return
                }
                
                // TODO: Phase 2 - Implement playlists list
                self.logger.debug("Show playlists")
                completion(false) // Not implemented yet
            }
        }
        
        return item
    }
    
    private func buildGenresItem() -> CPListItem {
        let item = CPListItem(text: "Genres", detailText: nil)
        
        item.handler = { [weak self] _, completion in
            Task { @MainActor [weak self] in
                guard let self = self else {
                    completion(false)
                    return
                }
                
                // TODO: Phase 2 - Implement genres list
                self.logger.debug("Show genres")
                completion(false) // Not implemented yet
            }
        }
        
        return item
    }
    
    private func buildArtistsItem() -> CPListItem {
        let item = CPListItem(text: "Artists", detailText: nil)
        
        item.handler = { [weak self] _, completion in
            Task { @MainActor [weak self] in
                guard let self = self else {
                    completion(false)
                    return
                }
                
                // TODO: Phase 2 - Implement artists list
                self.logger.debug("Show artists")
                completion(false) // Not implemented yet
            }
        }
        
        return item
    }
    
    private func buildAlbumsItem() -> CPListItem {
        let item = CPListItem(text: "Albums", detailText: nil)
        
        item.handler = { [weak self] _, completion in
            Task { @MainActor [weak self] in
                guard let self = self else {
                    completion(false)
                    return
                }
                
                // TODO: Phase 2 - Implement albums list
                self.logger.debug("Show albums")
                completion(false) // Not implemented yet
            }
        }
        
        return item
    }
    
    private func buildSongsItem() -> CPListItem {
        let item = CPListItem(text: "Songs", detailText: nil)
        
        item.handler = { [weak self] _, completion in
            Task { @MainActor [weak self] in
                guard let self = self else {
                    completion(false)
                    return
                }
                
                // TODO: Phase 2 - Implement songs list
                self.logger.debug("Show songs")
                completion(false) // Not implemented yet
            }
        }
        
        return item
    }
}

