
import CarPlay
import Combine
import CoreData

@MainActor
final class CarPlayHomeBuilder {
    private let logger = Log.make(.carPlay)
    
    private var playbackViewModel: PlaybackViewModel
    private var libraryRepository: LibraryRepository
    private var playbackRepository: PlaybackRepository
    private weak var interfaceController: CPInterfaceController?
    private var cancellables = Set<AnyCancellable>()
    
    private var activeServer: CDServer? {
        guard let serverId = AppCoordinator.shared?.activeServer?.id else { return nil }
        let context = CoreDataStack.shared.viewContext
        let request: NSFetchRequest<CDServer> = CDServer.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", serverId as CVarArg)
        request.fetchLimit = 1
        return try? context.fetch(request).first
    }
    
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
        
        let primaryActionsSection = buildPrimaryActionsSection()
        sections.append(primaryActionsSection)
        
        if let resumeSection = buildResumeSection() {
            sections.append(resumeSection)
        }
        
        let genreSection = buildGenreSection()
        sections.append(genreSection)
        
        let template = CPListTemplate(title: "Home", sections: sections)
        template.tabTitle = "Home"
        template.tabImage = UIImage(systemName: "house.fill")
        
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
        
        return template
    }
    
    private func buildResumeSection() -> CPListSection? {
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
                    completion()
                    return
                }
                
                if !self.playbackViewModel.isPlaying {
                    await self.playbackRepository.resume()
                    self.playbackViewModel.isPlaying = true
                }
                
                self.interfaceController?.pushTemplate(
                    CPNowPlayingTemplate.shared,
                    animated: true
                ) { _, _ in }
                
                completion()
            }
        }
        
        return CPListSection(items: [item], header: "Resume Listening", sectionIndexTitle: nil)
    }
    
    private func buildPrimaryActionsSection() -> CPListSection {
        var items: [CPListItem] = []
        
        let shuffleLikedItem = CPListItem(
            text: "Shuffle Liked",
            detailText: "Random from your liked tracks"
        )
        shuffleLikedItem.handler = { [weak self] _, completion in
            Task { @MainActor [weak self] in
                guard let self = self else {
                    completion()
                    return
                }
                await self.playShuffleLiked()
                completion()
            }
        }
        items.append(shuffleLikedItem)
        
        let recentlyPlayedItem = CPListItem(
            text: "Recently Played",
            detailText: "Last 50 tracks"
        )
        recentlyPlayedItem.handler = { [weak self] _, completion in
            Task { @MainActor [weak self] in
                guard let self = self else {
                    completion()
                    return
                }
                await self.playRecentlyPlayed()
                completion()
            }
        }
        items.append(recentlyPlayedItem)
        
        let recentlyAddedItem = CPListItem(
            text: "Recently Added",
            detailText: "500 most recent tracks"
        )
        recentlyAddedItem.handler = { [weak self] _, completion in
            Task { @MainActor [weak self] in
                guard let self = self else {
                    completion()
                    return
                }
                await self.playRecentlyAdded()
                completion()
            }
        }
        items.append(recentlyAddedItem)
        
        let shuffleAllItem = CPListItem(
            text: "Shuffle All",
            detailText: "Random from your entire library"
        )
        shuffleAllItem.handler = { [weak self] _, completion in
            Task { @MainActor [weak self] in
                guard let self = self else {
                    completion()
                    return
                }
                await self.playShuffleAll()
                completion()
            }
        }
        items.append(shuffleAllItem)
        
        return CPListSection(items: items, header: nil, sectionIndexTitle: nil)
    }
    
    private func buildGenreSection() -> CPListSection {
        guard let activeServer = activeServer else {
            return CPListSection(items: [], header: "Random by Genre", sectionIndexTitle: nil)
        }
        
        let context = CoreDataStack.shared.viewContext
        let umbrellaRequest: NSFetchRequest<CDGenre> = CDGenre.fetchRequest()
        umbrellaRequest.predicate = NSPredicate(format: "server == %@ AND umbrellaName != nil", activeServer)
        
        guard let allGenres = try? context.fetch(umbrellaRequest) else {
            return CPListSection(items: [], header: "Random by Genre", sectionIndexTitle: nil)
        }
        
        var genreTracks: [String: Set<CDTrack>] = [:]
        for genre in allGenres {
            guard let umbrellaName = genre.umbrellaName, !umbrellaName.isEmpty else { continue }
            if let tracks = genre.tracks as? Set<CDTrack> {
                let serverTracks = tracks.filter { $0.server == activeServer }
                if genreTracks[umbrellaName] == nil {
                    genreTracks[umbrellaName] = Set<CDTrack>()
                }
                genreTracks[umbrellaName]?.formUnion(serverTracks)
            }
        }
        
        let genreItems = genreTracks.map { name, tracks in
            (name: name, count: tracks.count)
        }.sorted { $0.count > $1.count }
        
        let items = genreItems.prefix(10).map { genreInfo -> CPListItem in
            let item = CPListItem(
                text: genreInfo.name,
                detailText: "\(genreInfo.count) songs"
            )
            
            item.handler = { [weak self] _, completion in
                Task { @MainActor [weak self] in
                    guard let self = self else {
                        completion()
                        return
                    }
                    
                    await self.playGenre(genreInfo.name)
                    completion()
                }
            }
            
            return item
        }
        
        return CPListSection(items: Array(items), header: "Random by Genre", sectionIndexTitle: nil)
    }
    
    private func playGenre(_ umbrellaGenre: String) async {
        guard let serverId = AppCoordinator.shared?.activeServer?.id else { return }
        
        let context = CoreDataStack.shared.viewContext
        let tracks: [Track] = await context.perform {
            let serverRequest: NSFetchRequest<CDServer> = CDServer.fetchRequest()
            serverRequest.predicate = NSPredicate(format: "id == %@", serverId as CVarArg)
            serverRequest.fetchLimit = 1
            
            guard let server = try? context.fetch(serverRequest).first else {
                return []
            }
            
            let trackRequest: NSFetchRequest<CDTrack> = CDTrack.fetchRequest()
            trackRequest.predicate = NSPredicate(format: "server == %@", server)
            
            guard let allTracks = try? context.fetch(trackRequest) else {
                return []
            }
            
            let genreTracks = allTracks.filter { cdTrack in
                guard let umbrellaGenres = cdTrack.umbrellaGenres as? [String] else {
                    return false
                }
                return umbrellaGenres.contains(umbrellaGenre)
            }
            
            let shuffled = genreTracks.shuffled().prefix(50)
            
            return shuffled.map { cdTrack in
                CoreDataTrackHelper.toDomain(cdTrack, serverId: serverId)
            }
        }
        
        guard !tracks.isEmpty else { return }
        
        playbackViewModel.startQueue(
            from: tracks,
            at: 0,
            context: .custom(tracks.map { $0.id })
        )
        
        interfaceController?.pushTemplate(
            CPNowPlayingTemplate.shared,
            animated: true
        ) { _, _ in }
    }
    
    private func playShuffleLiked() async {
        guard let serverId = AppCoordinator.shared?.activeServer?.id else { return }
        
        let context = CoreDataStack.shared.viewContext
        let tracks: [Track] = await context.perform {
            let serverRequest: NSFetchRequest<CDServer> = CDServer.fetchRequest()
            serverRequest.predicate = NSPredicate(format: "id == %@", serverId as CVarArg)
            serverRequest.fetchLimit = 1
            
            guard let server = try? context.fetch(serverRequest).first else {
                return []
            }
            
            let trackRequest: NSFetchRequest<CDTrack> = CDTrack.fetchRequest()
            trackRequest.predicate = NSPredicate(format: "server == %@ AND isLiked == YES", server)
            trackRequest.fetchLimit = 50
            
            guard let cdTracks = try? context.fetch(trackRequest) else {
                return []
            }
            
            let shuffled = cdTracks.shuffled().prefix(50)
            
            return shuffled.map { cdTrack in
                CoreDataTrackHelper.toDomain(cdTrack, serverId: serverId)
            }
        }
        
        guard !tracks.isEmpty else { return }
        
        playbackViewModel.startQueue(
            from: tracks,
            at: 0,
            context: .custom(tracks.map { $0.id })
        )
        
        interfaceController?.pushTemplate(
            CPNowPlayingTemplate.shared,
            animated: true
        ) { _, _ in }
    }
    
    private func playRecentlyPlayed() async {
        do {
            let tracks = try await libraryRepository.fetchRecentlyPlayed(limit: 50)
            guard !tracks.isEmpty else { return }
            
            playbackViewModel.startQueue(
                from: tracks,
                at: 0,
                context: .custom(tracks.map { $0.id })
            )
            
            interfaceController?.pushTemplate(
                CPNowPlayingTemplate.shared,
                animated: true
            ) { _, _ in }
        } catch {
            logger.error("playRecentlyPlayed: \(error.localizedDescription)")
        }
    }
    
    private func playRecentlyAdded() async {
        do {
            let tracks = try await libraryRepository.fetchRecentlyAdded(limit: 500)
            guard !tracks.isEmpty else { return }
            
            let sortedTracks = tracks.sorted { track1, track2 in
                let date1 = track1.dateAdded ?? Date.distantPast
                let date2 = track2.dateAdded ?? Date.distantPast
                return date1 > date2
            }
            
            playbackViewModel.startQueue(
                from: sortedTracks,
                at: 0,
                context: .custom(sortedTracks.map { $0.id })
            )
            
            interfaceController?.pushTemplate(
                CPNowPlayingTemplate.shared,
                animated: true
            ) { _, _ in }
        } catch {
            logger.error("playRecentlyAdded: \(error.localizedDescription)")
        }
    }
    
    private func playShuffleAll() async {
        guard AppCoordinator.shared?.activeServer?.id != nil else { return }
        
        do {
            let allTracks = try await libraryRepository.fetchTracks(albumId: nil)
            guard !allTracks.isEmpty else { return }
            
            let shuffled = allTracks.shuffled().prefix(500)
            let tracks = Array(shuffled)
            
            playbackViewModel.startQueue(
                from: tracks,
                at: 0,
                context: .custom(tracks.map { $0.id })
            )
            
            interfaceController?.pushTemplate(
                CPNowPlayingTemplate.shared,
                animated: true
            ) { _, _ in }
        } catch {
            logger.error("playShuffleAll: \(error.localizedDescription)")
        }
    }
}

