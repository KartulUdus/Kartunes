
import CarPlay
import UIKit

@MainActor
final class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {
    private let logger = Log.make(.carPlay)
    
    weak var interfaceController: CPInterfaceController?
    
    private var playbackViewModel: PlaybackViewModel?
    private var libraryRepository: LibraryRepository?
    private var playbackRepository: PlaybackRepository?
    
    private var nowPlayingCoordinator: CarPlayNowPlayingCoordinator?
    private var homeBuilder: CarPlayHomeBuilder?
    private var libraryBuilder: CarPlayLibraryBuilder?
    
    override init() {
        super.init()
        // Try to get coordinator from shared reference
        if let coordinator = AppCoordinator.shared {
            self.playbackViewModel = coordinator.playbackViewModel
            self.libraryRepository = coordinator.libraryRepository
            self.playbackRepository = coordinator.playbackRepository
        }
    }
    
    // Convenience initializer for testing or manual creation
    init(
        playbackViewModel: PlaybackViewModel,
        libraryRepository: LibraryRepository,
        playbackRepository: PlaybackRepository
    ) {
        self.playbackViewModel = playbackViewModel
        self.libraryRepository = libraryRepository
        self.playbackRepository = playbackRepository
        super.init()
    }
    
    func updateRepositories(
        playbackViewModel: PlaybackViewModel,
        libraryRepository: LibraryRepository,
        playbackRepository: PlaybackRepository
    ) {
        self.playbackViewModel = playbackViewModel
        self.libraryRepository = libraryRepository
        self.playbackRepository = playbackRepository
        
        // Update coordinators if they exist
        nowPlayingCoordinator?.updateRepositories(
            playbackViewModel: playbackViewModel,
            playbackRepository: playbackRepository
        )
        
        homeBuilder?.updateRepositories(
            playbackViewModel: playbackViewModel,
            libraryRepository: libraryRepository,
            playbackRepository: playbackRepository
        )
        
        libraryBuilder?.updateRepositories(
            libraryRepository: libraryRepository,
            playbackRepository: playbackRepository,
            playbackViewModel: playbackViewModel
        )
    }
    
    // MARK: - CPTemplateApplicationSceneDelegate
    
    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didConnect interfaceController: CPInterfaceController
    ) {
        logger.info("Scene connected")
        
        // Ensure we have the coordinator's repositories
        if playbackViewModel == nil || libraryRepository == nil || playbackRepository == nil {
            if let coordinator = AppCoordinator.shared {
                playbackViewModel = coordinator.playbackViewModel
                libraryRepository = coordinator.libraryRepository
                playbackRepository = coordinator.playbackRepository
            } else {
                logger.warning("AppCoordinator not available, using stub templates")
                self.interfaceController = interfaceController
                let tabBar = CPTabBarTemplate(templates: [buildStubHomeTemplate(), buildStubLibraryTemplate()])
                interfaceController.setRootTemplate(tabBar, animated: true)
                return
            }
        }
        
        guard let playbackViewModel = playbackViewModel,
              let libraryRepository = libraryRepository,
              let playbackRepository = playbackRepository else {
            logger.warning("Missing required dependencies")
            return
        }
        
        self.interfaceController = interfaceController
        
        // Create coordinators and builders
        nowPlayingCoordinator = CarPlayNowPlayingCoordinator(
            playbackViewModel: playbackViewModel,
            playbackRepository: playbackRepository
        )
        
        homeBuilder = CarPlayHomeBuilder(
            playbackViewModel: playbackViewModel,
            libraryRepository: libraryRepository,
            playbackRepository: playbackRepository,
            interfaceController: interfaceController
        )
        
        libraryBuilder = CarPlayLibraryBuilder(
            libraryRepository: libraryRepository,
            playbackRepository: playbackRepository,
            playbackViewModel: playbackViewModel,
            interfaceController: interfaceController
        )
        
        // Build root tab bar
        let homeTemplate = homeBuilder?.buildHomeTemplate() ?? buildStubHomeTemplate()
        let libraryTemplate = libraryBuilder?.buildLibraryRootTemplate() ?? buildStubLibraryTemplate()
        
        let tabBar = CPTabBarTemplate(templates: [homeTemplate, libraryTemplate])
        interfaceController.setRootTemplate(tabBar, animated: true)
        
        // Start Now Playing coordinator
        nowPlayingCoordinator?.start()
        
        // Register with coordinator
        AppCoordinator.shared?.carPlaySceneDelegate = self
    }
    
    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didDisconnect interfaceController: CPInterfaceController
    ) {
        logger.info("Scene disconnected")
        
        // Stop observers
        nowPlayingCoordinator?.stop()
        
        // Clean up
        self.interfaceController = nil
        nowPlayingCoordinator = nil
        homeBuilder = nil
        libraryBuilder = nil
    }
    
    // MARK: - Stub Templates (Phase 1)
    
    private func buildStubHomeTemplate() -> CPListTemplate {
        let section = CPListSection(
            items: [
                CPListItem(text: "Home", detailText: "CarPlay integration in progress")
            ]
        )
        return CPListTemplate(title: "Home", sections: [section])
    }
    
    private func buildStubLibraryTemplate() -> CPListTemplate {
        let section = CPListSection(
            items: [
                CPListItem(text: "Library", detailText: "CarPlay integration in progress")
            ]
        )
        return CPListTemplate(title: "Library", sections: [section])
    }
}

