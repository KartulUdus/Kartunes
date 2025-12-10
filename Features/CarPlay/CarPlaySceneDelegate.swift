
import CarPlay
import UIKit
import Combine

@objc(CarPlaySceneDelegate)
class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {
    private let logger = Log.make(.carPlay)
    
    weak var interfaceController: CPInterfaceController?
    
    private var playbackViewModel: PlaybackViewModel?
    private var libraryRepository: LibraryRepository?
    private var playbackRepository: PlaybackRepository?
    
    private var nowPlayingCoordinator: CarPlayNowPlayingCoordinator?
    private var homeBuilder: CarPlayHomeBuilder?
    private var libraryBuilder: CarPlayLibraryBuilder?
    private var queueCancellable: AnyCancellable?
    
    override init() {
        super.init()
        if let coordinator = AppCoordinator.shared {
            self.playbackViewModel = coordinator.playbackViewModel
            self.libraryRepository = coordinator.libraryRepository
            self.playbackRepository = coordinator.playbackRepository
        }
    }
    
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
        
        nowPlayingCoordinator?.updateRepositories(
            playbackViewModel: playbackViewModel,
            playbackRepository: playbackRepository,
            libraryRepository: libraryRepository
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
    
    @objc
    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didConnect interfaceController: CPInterfaceController
    ) {
        assert(Thread.isMainThread, "CarPlay delegate methods must be called on main thread")
        handleCarPlayConnection(interfaceController: interfaceController)
    }

    @objc
    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didDisconnectInterfaceController interfaceController: CPInterfaceController
    ) {
        assert(Thread.isMainThread, "CarPlay delegate methods must be called on main thread")
        handleCarPlayDisconnection()
    }
    
    @objc
    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didConnect interfaceController: CPInterfaceController,
        to window: CPWindow
    ) {
        if window.rootViewController == nil {
            window.rootViewController = UIViewController()
        }
        handleCarPlayConnection(interfaceController: interfaceController)
    }

    @objc
    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didDisconnect interfaceController: CPInterfaceController,
        from window: CPWindow
    ) {
        window.rootViewController = nil
        handleCarPlayDisconnection()
    }
    
    private func handleCarPlayConnection(interfaceController: CPInterfaceController) {
        if playbackViewModel == nil || libraryRepository == nil || playbackRepository == nil {
            if let coordinator = AppCoordinator.shared {
                playbackViewModel = coordinator.playbackViewModel
                libraryRepository = coordinator.libraryRepository
                playbackRepository = coordinator.playbackRepository
            } else {
                self.interfaceController = interfaceController
                let tabBar = CPTabBarTemplate(templates: [buildStubHomeTemplate(), buildStubLibraryTemplate()])
                interfaceController.setRootTemplate(tabBar, animated: true) { _, _ in }
                return
            }
        }
        
        guard let playbackViewModel = playbackViewModel,
              let libraryRepository = libraryRepository,
              let playbackRepository = playbackRepository else {
            return
        }
        
        self.interfaceController = interfaceController
        
        nowPlayingCoordinator = CarPlayNowPlayingCoordinator(
            playbackViewModel: playbackViewModel,
            playbackRepository: playbackRepository,
            libraryRepository: libraryRepository
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
        
        let nowPlayingTemplate = buildNowPlayingTemplate()
        let homeTemplate = homeBuilder?.buildHomeTemplate() ?? buildStubHomeTemplate()
        let libraryTemplate = libraryBuilder?.buildLibraryRootTemplate() ?? buildStubLibraryTemplate()
        
        let templates: [CPTemplate] = [homeTemplate, libraryTemplate, nowPlayingTemplate]
        let tabBar = CPTabBarTemplate(templates: templates)
        
        let isPlaying = playbackViewModel.currentTrack != nil && !playbackViewModel.queue.isEmpty
        
        interfaceController.setRootTemplate(tabBar, animated: true) { [weak self] _, _ in
            if isPlaying {
                self?.interfaceController?.pushTemplate(
                    CPNowPlayingTemplate.shared,
                    animated: true
                ) { _, _ in }
            }
        }
        
        nowPlayingCoordinator?.start()
        observeQueueChanges()
        AppCoordinator.shared?.setCarPlaySceneDelegate(self)
    }
    
    private func handleCarPlayDisconnection() {
        nowPlayingCoordinator?.stop()
        queueCancellable?.cancel()
        queueCancellable = nil
        self.interfaceController = nil
        nowPlayingCoordinator = nil
        homeBuilder = nil
        libraryBuilder = nil
    }
    
    private func observeQueueChanges() {
        guard let playbackViewModel = playbackViewModel else { return }
        
        queueCancellable = Publishers.CombineLatest(
            playbackViewModel.$queue,
            playbackViewModel.$currentTrack
        )
        .debounce(for: .milliseconds(100), scheduler: DispatchQueue.main)
        .sink { [weak self] _ in
            self?.updateQueueTemplate()
        }
    }
    
    private func updateQueueTemplate() {
        guard let template = nowPlayingTemplate else { return }
        
        let upNextTracks = playbackViewModel?.getUpNextTracks() ?? []
        
        let items: [CPListItem] = if upNextTracks.isEmpty {
            [CPListItem(
                text: "No upcoming tracks",
                detailText: "Start playing music to see your queue"
            )]
        } else {
            upNextTracks.map { track in
                let isCurrentlyPlaying = track.id == playbackViewModel?.currentTrack?.id
                let displayText = isCurrentlyPlaying ? "▶ \(track.title)" : track.title
                let item = CPListItem(
                    text: displayText,
                    detailText: "\(track.artistName) • \(formatDuration(track.duration))"
                )
                
                item.handler = { [weak self] (_: CPSelectableListItem, completion: @escaping () -> Void) in
                    guard let self = self,
                          let viewModel = self.playbackViewModel,
                          let queueIndex = viewModel.queue.firstIndex(where: { $0.id == track.id }) else {
                        completion()
                        return
                    }
                    viewModel.skipTo(index: queueIndex)
                    completion()
                }
                
                return item
            }
        }
        
        let section = CPListSection(items: items, header: "Queue", sectionIndexTitle: nil)
        template.updateSections([section])
    }
    
    private var nowPlayingTemplate: CPListTemplate?
    
    private func buildNowPlayingTemplate() -> CPListTemplate {
        let upNextTracks = playbackViewModel?.getUpNextTracks() ?? []
        
        let items: [CPListItem] = if upNextTracks.isEmpty {
            [CPListItem(
                text: "No upcoming tracks",
                detailText: "Start playing music to see your queue"
            )]
        } else {
            upNextTracks.map { track in
                let isCurrentlyPlaying = track.id == playbackViewModel?.currentTrack?.id
                let displayText = isCurrentlyPlaying ? "▶ \(track.title)" : track.title
                let item = CPListItem(
                    text: displayText,
                    detailText: "\(track.artistName) • \(formatDuration(track.duration))"
                )
                
                item.handler = { [weak self] (_: CPSelectableListItem, completion: @escaping () -> Void) in
                    guard let self = self,
                          let viewModel = self.playbackViewModel,
                          let queueIndex = viewModel.queue.firstIndex(where: { $0.id == track.id }) else {
                        completion()
                        return
                    }
                    viewModel.skipTo(index: queueIndex)
                    completion()
                }
                
                return item
            }
        }
        
        let section = CPListSection(items: items, header: "Queue", sectionIndexTitle: nil)
        let template = CPListTemplate(title: "Queue", sections: [section])
        template.tabTitle = "Queue"
        template.tabImage = UIImage(systemName: "list.bullet")
        
        let playButton = CPBarButton(
            image: UIImage(systemName: "play.circle.fill") ?? UIImage(systemName: "play.fill")!
        ) { [weak self] _ in
            guard let self = self else { return }
            self.interfaceController?.pushTemplate(
                CPNowPlayingTemplate.shared,
                animated: true
            ) { (_: Bool, _: Error?) in }
        }
        template.leadingNavigationBarButtons = []
        template.trailingNavigationBarButtons = [playButton]
        
        self.nowPlayingTemplate = template
        return template
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        guard duration.isFinite && !duration.isNaN && duration >= 0 else {
            return "0:00"
        }
        let totalSeconds = Int(duration.rounded())
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
    
    private func buildStubHomeTemplate() -> CPListTemplate {
        let section = CPListSection(
            items: [
                CPListItem(text: "Home", detailText: "CarPlay integration in progress")
            ]
        )
        let template = CPListTemplate(title: "Home", sections: [section])
        template.tabTitle = "Home"
        template.tabImage = UIImage(systemName: "house.fill")
        return template
    }
    
    private func buildStubLibraryTemplate() -> CPListTemplate {
        let section = CPListSection(
            items: [
                CPListItem(text: "Library", detailText: "CarPlay integration in progress")
            ]
        )
        let template = CPListTemplate(title: "Library", sections: [section])
        template.tabTitle = "Library"
        template.tabImage = UIImage(systemName: "music.note.list")
        return template
    }
}
