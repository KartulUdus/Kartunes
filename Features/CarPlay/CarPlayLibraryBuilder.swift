
import CarPlay
import CoreData

@MainActor
final class CarPlayLibraryBuilder {
    private let logger = Log.make(.carPlay)
    
    private var libraryRepository: LibraryRepository
    private var playbackRepository: PlaybackRepository
    private var playbackViewModel: PlaybackViewModel
    private weak var interfaceController: CPInterfaceController?
    
    private var activeServer: CDServer? {
        guard let serverId = AppCoordinator.shared?.activeServer?.id else { return nil }
        let context = CoreDataStack.shared.viewContext
        let request: NSFetchRequest<CDServer> = CDServer.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", serverId as CVarArg)
        request.fetchLimit = 1
        return try? context.fetch(request).first
    }
    
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
        
        let section = CPListSection(items: items, header: nil, sectionIndexTitle: nil)
        let template = CPListTemplate(title: "Library", sections: [section])
        template.tabTitle = "Library"
        template.tabImage = UIImage(systemName: "music.note.list")
        
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
    
    private func buildPlaylistsItem() -> CPListItem {
        let item = CPListItem(text: "Playlists", detailText: nil)
        
        item.handler = { [weak self] _, completion in
            Task { @MainActor [weak self] in
                guard let self = self else {
                    completion()
                    return
                }
                
                await self.showPlaylists()
                completion()
            }
        }
        
        return item
    }
    
    private func buildGenresItem() -> CPListItem {
        let item = CPListItem(text: "Genres", detailText: nil)
        
        item.handler = { [weak self] _, completion in
            Task { @MainActor [weak self] in
                guard let self = self else {
                    completion()
                    return
                }
                
                await self.showGenres()
                completion()
            }
        }
        
        return item
    }
    
    private func buildArtistsItem() -> CPListItem {
        let item = CPListItem(text: "Artists", detailText: nil)
        
        item.handler = { [weak self] _, completion in
            Task { @MainActor [weak self] in
                guard let self = self else {
                    completion()
                    return
                }
                
                await self.showArtists()
                completion()
            }
        }
        
        return item
    }
    
    private func buildAlbumsItem() -> CPListItem {
        let item = CPListItem(text: "Albums", detailText: nil)
        
        item.handler = { [weak self] _, completion in
            Task { @MainActor [weak self] in
                guard let self = self else {
                    completion()
                    return
                }
                
                await self.showAlbums()
                completion()
            }
        }
        
        return item
    }
    
    private func buildSongsItem() -> CPListItem {
        let item = CPListItem(text: "Songs", detailText: nil)
        
        item.handler = { [weak self] _, completion in
            Task { @MainActor [weak self] in
                guard let self = self else {
                    completion()
                    return
                }
                
                await self.showSongs()
                completion()
            }
        }
        
        return item
    }
    
    private func createAlphabeticalSections<T>(
        from items: [T],
        getTitle: (T) -> String,
        createItem: (T) -> CPListItem
    ) -> [CPListSection] {
        guard !items.isEmpty else {
            return []
        }
        
        let grouped = Dictionary(grouping: items) { item -> String in
            let title = getTitle(item)
            guard let firstChar = title.uppercased().first, firstChar.isLetter else {
                return "#"
            }
            return String(firstChar)
        }
        
        let sortedKeys = grouped.keys.sorted { key1, key2 in
            if key1 == "#" { return false }
            if key2 == "#" { return true }
            return key1 < key2
        }
        
        return sortedKeys.map { key in
            let groupItems = grouped[key] ?? []
            let sortedGroupItems = groupItems.sorted { item1, item2 in
                getTitle(item1).localizedCompare(getTitle(item2)) == .orderedAscending
            }
            let sectionItems = sortedGroupItems.map(createItem)
            return CPListSection(items: sectionItems, header: nil, sectionIndexTitle: key)
        }
    }
    
    private func showPlaylists() async {
        do {
            let playlists = try await libraryRepository.fetchPlaylists()
            
            let sortedPlaylists = playlists.sorted { playlist1, playlist2 in
                let editable1 = playlist1.isEditable
                let editable2 = playlist2.isEditable
                
                if editable1 != editable2 {
                    return editable1
                }
                
                return playlist1.name.localizedCompare(playlist2.name) == .orderedAscending
            }
            
            let items = sortedPlaylists.map { playlist -> CPListItem in
                let item = CPListItem(
                    text: playlist.name,
                    detailText: playlist.summary
                )
                
                item.handler = { [weak self] _, completion in
                    Task { @MainActor [weak self] in
                        guard let self = self else {
                            completion()
                            return
                        }
                        await self.showPlaylistTracks(playlistId: playlist.id)
                        completion()
                    }
                }
                
                return item
            }
            
            let section = CPListSection(items: items, header: "Playlists", sectionIndexTitle: nil)
            let template = CPListTemplate(title: "Playlists", sections: [section])
            interfaceController?.pushTemplate(template, animated: true) { _, _ in }
        } catch {
            logger.error("Failed to fetch playlists: \(error.localizedDescription)")
        }
    }
    
    private func showGenres() async {
        guard let activeServer = activeServer else { return }
        let serverObjectID = activeServer.objectID
        
        let context = CoreDataStack.shared.viewContext
        let genres: [(name: String, count: Int)] = await context.perform {
            // Fetch the server using its objectID to avoid Sendable issues
            guard let server = try? context.existingObject(with: serverObjectID) as? CDServer else {
                return []
            }
            
            let request: NSFetchRequest<CDGenre> = CDGenre.fetchRequest()
            request.predicate = NSPredicate(format: "server == %@ AND umbrellaName != nil", server)
            
            guard let allGenres = try? context.fetch(request) else { return [] }
            
            var genreTracks: [String: Set<CDTrack>] = [:]
            for genre in allGenres {
                guard let umbrellaName = genre.umbrellaName, !umbrellaName.isEmpty else { continue }
                if let tracks = genre.tracks as? Set<CDTrack> {
                    let serverTracks = tracks.filter { $0.server == server }
                    if genreTracks[umbrellaName] == nil {
                        genreTracks[umbrellaName] = Set<CDTrack>()
                    }
                    genreTracks[umbrellaName]?.formUnion(serverTracks)
                }
            }
            
            return genreTracks.map { name, tracks in
                (name: name, count: tracks.count)
            }.sorted { $0.count > $1.count }
        }
        
        let items = genres.map { genreInfo -> CPListItem in
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
        
        let section = CPListSection(items: items, header: "Genres", sectionIndexTitle: nil)
        let template = CPListTemplate(title: "Genres", sections: [section])
        interfaceController?.pushTemplate(template, animated: true) { _, _ in }
    }
    
    private func showArtists() async {
        guard let activeServer = activeServer else { return }
        
        let context = CoreDataStack.shared.viewContext
        let artists: [Artist] = await context.perform {
            let request: NSFetchRequest<CDArtist> = CDArtist.fetchRequest()
            request.predicate = NSPredicate(format: "server == %@", activeServer)
            request.sortDescriptors = [NSSortDescriptor(key: "sortName", ascending: true)]
            
            guard let cdArtists = try? context.fetch(request) else {
                return []
            }
            
            return cdArtists.map { cdArtist in
                Artist(
                    id: cdArtist.id ?? "",
                    name: cdArtist.name ?? "",
                    thumbnailURL: cdArtist.imageURL.flatMap { URL(string: $0) }
                )
            }
        }
        
        logger.debug("Fetched \(artists.count) artists from CoreData")
        
        let maxItems = CPListTemplate.maximumItemCount
        logger.info("CarPlay limits: maxItems=\(maxItems)")
        
        if artists.count > maxItems {
            showArtistsByLetter(artists: artists, maxItems: maxItems)
        } else {
            showAllArtists(artists: artists)
        }
    }
    
    private func showArtistsByLetter(artists: [Artist], maxItems: Int) {
        let grouped = Dictionary(grouping: artists) { artist -> String in
            let title = artist.name
            guard let firstChar = title.uppercased().first, firstChar.isLetter else {
                return "#"
            }
            return String(firstChar)
        }
        
        let sortedKeys = grouped.keys.sorted { key1, key2 in
            if key1 == "#" { return false }
            if key2 == "#" { return true }
            return key1 < key2
        }
        
        let items = sortedKeys.map { letter -> CPListItem in
            let count = grouped[letter]?.count ?? 0
            let item = CPListItem(
                text: letter,
                detailText: "\(count) artist\(count == 1 ? "" : "s")"
            )
            
            item.handler = { [weak self] _, completion in
                Task { @MainActor [weak self] in
                    guard let self = self, let letterArtists = grouped[letter] else {
                        completion()
                        return
                    }
                    await self.showArtistsForLetter(letter: letter, artists: letterArtists, maxItems: maxItems)
                    completion()
                }
            }
            
            return item
        }
        
        let section = CPListSection(items: items, header: "Browse by Letter", sectionIndexTitle: nil)
        let template = CPListTemplate(title: "Artists", sections: [section])
        interfaceController?.pushTemplate(template, animated: true) { _, _ in }
    }
    
    private func showArtistsForLetter(letter: String, artists: [Artist], maxItems: Int) async {
        let sortedArtists = artists.sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
        
        let sections = createAlphabeticalSections(
            from: sortedArtists,
            getTitle: { $0.name },
            createItem: { artist -> CPListItem in
                let item = CPListItem(
                    text: artist.name,
                    detailText: nil
                )
                
                item.handler = { [weak self] _, completion in
                    Task { @MainActor [weak self] in
                        guard let self = self else {
                            completion()
                            return
                        }
                        await self.showArtistAlbums(artistId: artist.id, artistName: artist.name)
                        completion()
                    }
                }
                
                return item
            }
        )
        
        let clampedSections = clampSectionsToLimit(sections, maxItems: maxItems, maxSections: CPListTemplate.maximumSectionCount)
        
        let template = CPListTemplate(title: "Artists - \(letter)", sections: clampedSections)
        interfaceController?.pushTemplate(template, animated: true) { _, _ in }
    }
    
    private func showAllArtists(artists: [Artist]) {
        let sortedArtists = artists.sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
        
        let sections = createAlphabeticalSections(
            from: sortedArtists,
            getTitle: { $0.name },
            createItem: { artist -> CPListItem in
                let item = CPListItem(
                    text: artist.name,
                    detailText: nil
                )
                
                item.handler = { [weak self] _, completion in
                    Task { @MainActor [weak self] in
                        guard let self = self else {
                            completion()
                            return
                        }
                        await self.showArtistAlbums(artistId: artist.id, artistName: artist.name)
                        completion()
                    }
                }
                
                return item
            }
        )
        
        let clampedSections = clampSectionsToLimit(sections, maxItems: CPListTemplate.maximumItemCount, maxSections: CPListTemplate.maximumSectionCount)
        
        let template = CPListTemplate(title: "Artists", sections: clampedSections)
        interfaceController?.pushTemplate(template, animated: true) { _, _ in }
    }
    
    private func clampSectionsToLimit(_ sections: [CPListSection], maxItems: Int, maxSections: Int) -> [CPListSection] {
        var remaining = maxItems
        var clamped: [CPListSection] = []
        
        for section in sections.prefix(maxSections) {
            if remaining <= 0 { break }
            
            let items = Array(section.items.prefix(remaining))
            if !items.isEmpty {
                let clampedSection = CPListSection(
                    items: items,
                    header: section.header,
                    sectionIndexTitle: section.sectionIndexTitle
                )
                clamped.append(clampedSection)
                remaining -= items.count
            }
        }
        
        return clamped
    }
    
    private func showAlbums() async {
        do {
            let albums = try await libraryRepository.fetchAlbums(artistId: nil)
            let sortedAlbums = albums.sorted { $0.title.localizedCompare($1.title) == .orderedAscending }
            
            let sections = createAlphabeticalSections(
                from: sortedAlbums,
                getTitle: { $0.title },
                createItem: { album -> CPListItem in
                    let item = CPListItem(
                        text: album.title,
                        detailText: album.artistName
                    )
                    
                    item.handler = { [weak self] _, completion in
                        Task { @MainActor [weak self] in
                            guard let self = self else {
                                completion()
                                return
                            }
                            await self.showAlbumTracks(albumId: album.id, albumTitle: album.title)
                            completion()
                        }
                    }
                    
                    return item
                }
            )
            
            let template = CPListTemplate(title: "Albums", sections: sections)
            interfaceController?.pushTemplate(template, animated: true) { _, _ in }
        } catch {
            logger.error("Failed to fetch albums: \(error.localizedDescription)")
        }
    }
    
    private func showSongs() async {
        do {
            let tracks = try await libraryRepository.fetchTracks(albumId: nil)
            let limitedTracks = Array(tracks.prefix(500))
            let sortedTracks = limitedTracks.sorted { $0.title.localizedCompare($1.title) == .orderedAscending }
            
            let sections = createAlphabeticalSections(
                from: sortedTracks,
                getTitle: { $0.title },
                createItem: { track -> CPListItem in
                    let item = CPListItem(
                        text: track.title,
                        detailText: "\(track.artistName) - \(track.albumTitle ?? "Unknown Album")"
                    )
                    
                    item.handler = { [weak self] _, completion in
                        Task { @MainActor [weak self] in
                            guard let self = self else {
                                completion()
                                return
                            }
                            await self.playTrack(track: track, from: limitedTracks)
                            completion()
                        }
                    }
                    
                    return item
                }
            )
            
            let template = CPListTemplate(title: "Songs", sections: sections)
            interfaceController?.pushTemplate(template, animated: true) { _, _ in }
        } catch {
            logger.error("Failed to fetch songs: \(error.localizedDescription)")
        }
    }
    
    private func showPlaylistTracks(playlistId: String) async {
        do {
            let tracks = try await libraryRepository.fetchPlaylistTracks(playlistId: playlistId)
            let items = tracks.map { track -> CPListItem in
                let item = CPListItem(
                    text: track.title,
                    detailText: "\(track.artistName) - \(track.albumTitle ?? "Unknown Album")"
                )
                
                item.handler = { [weak self] _, completion in
                    Task { @MainActor [weak self] in
                        guard let self = self else {
                            completion()
                            return
                        }
                        await self.playTrack(track: track, from: tracks)
                        completion()
                    }
                }
                
                return item
            }
            
            let section = CPListSection(items: items, header: "Tracks", sectionIndexTitle: nil)
            let template = CPListTemplate(title: "Playlist", sections: [section])
            interfaceController?.pushTemplate(template, animated: true) { _, _ in }
        } catch {
            logger.error("Failed to fetch playlist tracks: \(error.localizedDescription)")
        }
    }
    
    private func showArtistAlbums(artistId: String, artistName: String) async {
        do {
            let tracks = try await libraryRepository.fetchTracks(artistId: artistId)
            
            let sections: [CPListSection]
            if tracks.isEmpty {
                let errorItem = CPListItem(
                    text: "No tracks found",
                    detailText: "This artist has no tracks in your library"
                )
                sections = [CPListSection(items: [errorItem], header: nil, sectionIndexTitle: nil)]
            } else {
                let sortedTracks = tracks.sorted { $0.title.localizedCompare($1.title) == .orderedAscending }
                sections = createAlphabeticalSections(
                    from: sortedTracks,
                    getTitle: { $0.title },
                    createItem: { track -> CPListItem in
                        let item = CPListItem(
                            text: track.title,
                            detailText: track.albumTitle ?? nil
                        )
                        
                        item.handler = { [weak self] _, completion in
                            Task { @MainActor [weak self] in
                                guard let self = self else {
                                    completion()
                                    return
                                }
                                await self.playTrack(track: track, from: tracks)
                                completion()
                            }
                        }
                        
                        return item
                    }
                )
            }
            
            let template = CPListTemplate(title: artistName, sections: sections)
            
            guard let serverId = AppCoordinator.shared?.activeServer?.id,
                  let serverType = AppCoordinator.shared?.activeServer?.serverType else {
                interfaceController?.pushTemplate(template, animated: true) { _, _ in }
                return
            }
            
            if serverType != .emby {
                let radioButton = CPBarButton(
                    image: UIImage(systemName: "radio") ?? UIImage(systemName: "play.fill")!
                ) { [weak self] _ in
                    Task { @MainActor [weak self] in
                        guard let self = self else { return }
                        self.playbackViewModel.startInstantMix(from: artistId, kind: .artist, serverId: serverId)
                        self.interfaceController?.pushTemplate(
                            CPNowPlayingTemplate.shared,
                            animated: true
                        ) { _, _ in }
                    }
                }
                
                template.leadingNavigationBarButtons = []
                template.trailingNavigationBarButtons = [radioButton]
            }
            
            interfaceController?.pushTemplate(template, animated: true) { _, _ in }
        } catch {
            logger.error("Failed to fetch artist tracks: \(error.localizedDescription)")
            let errorItem = CPListItem(
                text: "Error loading tracks",
                detailText: error.localizedDescription
            )
            let section = CPListSection(items: [errorItem], header: nil, sectionIndexTitle: nil)
            let template = CPListTemplate(title: artistName, sections: [section])
            interfaceController?.pushTemplate(template, animated: true) { _, _ in }
        }
    }
    
    private func showAlbumTracks(albumId: String, albumTitle: String) async {
        do {
            let tracks = try await libraryRepository.fetchTracks(albumId: albumId)
            let items = tracks.map { track -> CPListItem in
                let item = CPListItem(
                    text: track.title,
                    detailText: track.trackNumber.map { "Track \($0)" } ?? nil
                )
                
                item.handler = { [weak self] _, completion in
                    Task { @MainActor [weak self] in
                        guard let self = self else {
                            completion()
                            return
                        }
                        await self.playTrack(track: track, from: tracks)
                        completion()
                    }
                }
                
                return item
            }
            
            let section = CPListSection(items: items, header: "Tracks", sectionIndexTitle: nil)
            let template = CPListTemplate(title: albumTitle, sections: [section])
            
            guard let serverId = AppCoordinator.shared?.activeServer?.id else {
                interfaceController?.pushTemplate(template, animated: true) { _, _ in }
                return
            }
            
            let radioButton = CPBarButton(
                image: UIImage(systemName: "radio") ?? UIImage(systemName: "play.fill")!
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self = self else { return }
                    self.playbackViewModel.startInstantMix(from: albumId, kind: .album, serverId: serverId)
                    self.interfaceController?.pushTemplate(
                        CPNowPlayingTemplate.shared,
                        animated: true
                    ) { _, _ in }
                }
            }
            
            template.leadingNavigationBarButtons = []
            template.trailingNavigationBarButtons = [radioButton]
            
            interfaceController?.pushTemplate(template, animated: true) { _, _ in }
        } catch {
            logger.error("Failed to fetch album tracks: \(error.localizedDescription)")
        }
    }
    
    private func playTrack(track: Track, from tracks: [Track]) async {
        guard let index = tracks.firstIndex(where: { $0.id == track.id }) else { return }
        
        playbackViewModel.startQueue(
            from: tracks,
            at: index,
            context: .custom(tracks.map { $0.id })
        )
        
        interfaceController?.pushTemplate(
            CPNowPlayingTemplate.shared,
            animated: true
        ) { _, _ in }
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
}

