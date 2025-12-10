
import CarPlay
import MediaPlayer
import Combine
import UIKit
@preconcurrency import CoreData

@MainActor
final class CarPlayNowPlayingCoordinator {
    private let logger = Log.make(.carPlay)
    
    private var playbackViewModel: PlaybackViewModel
    private var playbackRepository: PlaybackRepository
    private var libraryRepository: LibraryRepository?
    private var cancellables = Set<AnyCancellable>()
    
    private var skipAhead10Button: CPNowPlayingImageButton?
    private var shuffleButton: CPNowPlayingImageButton?
    private var repeatButton: CPNowPlayingImageButton?
    private var heartButton: CPNowPlayingImageButton?
    private var radioButton: CPNowPlayingImageButton?
    
    init(
        playbackViewModel: PlaybackViewModel,
        playbackRepository: PlaybackRepository,
        libraryRepository: LibraryRepository? = nil
    ) {
        self.playbackViewModel = playbackViewModel
        self.playbackRepository = playbackRepository
        self.libraryRepository = libraryRepository
    }
    
    func updateRepositories(
        playbackViewModel: PlaybackViewModel,
        playbackRepository: PlaybackRepository,
        libraryRepository: LibraryRepository? = nil
    ) {
        stop()
        self.playbackViewModel = playbackViewModel
        self.playbackRepository = playbackRepository
        self.libraryRepository = libraryRepository
        start()
    }
    
    func start() {
        setupRemoteCommands()
        setupObservers()
        createCustomButtons()
        syncInitialState()
        updateNowPlayingButtons()
    }
    
    private func syncInitialState() {
        let commandCenter = MPRemoteCommandCenter.shared()
        let repeatType: MPRepeatType = {
            switch playbackViewModel.repeatMode {
            case .off: return .off
            case .one: return .one
            case .all: return .all
            }
        }()
        commandCenter.changeRepeatModeCommand.currentRepeatType = repeatType
        repeatButton?.isSelected = (playbackViewModel.repeatMode != .off)
        
        commandCenter.changeShuffleModeCommand.currentShuffleType = playbackViewModel.isShuffleEnabled ? .items : .off
        shuffleButton?.isSelected = playbackViewModel.isShuffleEnabled
    }
    
    func stop() {
        cancellables.removeAll()
        removeRemoteCommands()
    }
    
    private func setupRemoteCommands() {
        let commandCenter = MPRemoteCommandCenter.shared()
        
        commandCenter.playCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.playbackRepository.resume()
                self?.playbackViewModel.isPlaying = true
            }
            return .success
        }
        
        commandCenter.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.playbackRepository.pause()
                self?.playbackViewModel.isPlaying = false
            }
            return .success
        }
        
        commandCenter.togglePlayPauseCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in
                if self?.playbackViewModel.isPlaying == true {
                    await self?.playbackRepository.pause()
                    self?.playbackViewModel.isPlaying = false
                } else {
                    await self?.playbackRepository.resume()
                    self?.playbackViewModel.isPlaying = true
                }
            }
            return .success
        }
        
        commandCenter.nextTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.playbackViewModel.skipForwardTrack()
            }
            return .success
        }
        
        commandCenter.previousTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.playbackViewModel.skipBackOrRestart()
            }
            return .success
        }
        
        commandCenter.skipForwardCommand.isEnabled = false
        commandCenter.skipBackwardCommand.isEnabled = false
        
        commandCenter.changeShuffleModeCommand.isEnabled = true
        commandCenter.changeShuffleModeCommand.currentShuffleType = playbackViewModel.isShuffleEnabled ? .items : .off
        commandCenter.changeShuffleModeCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangeShuffleModeCommandEvent,
                  let self = self else { return .commandFailed }
            Task { @MainActor [weak self] in
                let shuffleMode: MPShuffleType = event.shuffleType
                self?.playbackViewModel.isShuffleEnabled = (shuffleMode == .items)
                MPRemoteCommandCenter.shared().changeShuffleModeCommand.currentShuffleType = shuffleMode
            }
            return .success
        }
        
        commandCenter.changeRepeatModeCommand.isEnabled = true
        let currentRepeatType: MPRepeatType = {
            switch playbackViewModel.repeatMode {
            case .off: return .off
            case .one: return .one
            case .all: return .all
            }
        }()
        commandCenter.changeRepeatModeCommand.currentRepeatType = currentRepeatType
        commandCenter.changeRepeatModeCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangeRepeatModeCommandEvent,
                  let self = self else { return .commandFailed }
            Task { @MainActor [weak self] in
                let repeatType = event.repeatType
                switch repeatType {
                case .off:
                    self?.playbackViewModel.repeatMode = .off
                case .one:
                    self?.playbackViewModel.repeatMode = .one
                case .all:
                    self?.playbackViewModel.repeatMode = .all
                @unknown default:
                    self?.playbackViewModel.repeatMode = .off
                }
                MPRemoteCommandCenter.shared().changeRepeatModeCommand.currentRepeatType = repeatType
            }
            return .success
        }
        
        commandCenter.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            Task { @MainActor [weak self] in
                await self?.playbackRepository.seek(to: event.positionTime)
            }
            return .success
        }
        
        commandCenter.playCommand.isEnabled = true
        commandCenter.pauseCommand.isEnabled = true
        commandCenter.togglePlayPauseCommand.isEnabled = true
        commandCenter.nextTrackCommand.isEnabled = true
        commandCenter.previousTrackCommand.isEnabled = true
        commandCenter.changePlaybackPositionCommand.isEnabled = true
    }
    
    private func removeRemoteCommands() {
        let commandCenter = MPRemoteCommandCenter.shared()
        commandCenter.playCommand.removeTarget(nil)
        commandCenter.pauseCommand.removeTarget(nil)
        commandCenter.togglePlayPauseCommand.removeTarget(nil)
        commandCenter.nextTrackCommand.removeTarget(nil)
        commandCenter.previousTrackCommand.removeTarget(nil)
        commandCenter.changePlaybackPositionCommand.removeTarget(nil)
        commandCenter.changeShuffleModeCommand.removeTarget(nil)
        commandCenter.changeRepeatModeCommand.removeTarget(nil)
    }
    
    private func setupObservers() {
        playbackViewModel.$currentTrack
            .sink { [weak self] track in
                self?.updateNowPlayingInfo(for: track)
                self?.updateHeartButton(for: track)
            }
            .store(in: &cancellables)
        
        playbackViewModel.$isPlaying
            .sink { [weak self] isPlaying in
                self?.updatePlaybackState(isPlaying: isPlaying)
            }
            .store(in: &cancellables)
        
        playbackViewModel.$isShuffleEnabled
            .sink { [weak self] isEnabled in
                guard let self = self else { return }
                let commandCenter = MPRemoteCommandCenter.shared()
                commandCenter.changeShuffleModeCommand.currentShuffleType = isEnabled ? .items : .off
                self.shuffleButton?.isSelected = isEnabled
                self.updateNowPlayingButtons()
                self.updateNowPlayingInfo(for: self.playbackViewModel.currentTrack)
            }
            .store(in: &cancellables)
        
        playbackViewModel.$repeatMode
            .sink { [weak self] repeatMode in
                guard let self = self else { return }
                let commandCenter = MPRemoteCommandCenter.shared()
                let repeatType: MPRepeatType = {
                    switch repeatMode {
                    case .off: return .off
                    case .one: return .one
                    case .all: return .all
                    }
                }()
                commandCenter.changeRepeatModeCommand.currentRepeatType = repeatType
                
                let imageName = (repeatMode == .one) ? "repeat.1" : "repeat"
                if let image = UIImage(systemName: imageName) {
                    self.updateRepeatButtonImage(image, for: repeatMode)
                }
                
                self.repeatButton?.isSelected = (repeatMode != .off)
                self.updateNowPlayingInfo(for: self.playbackViewModel.currentTrack)
            }
            .store(in: &cancellables)
        
        playbackViewModel.$currentTime
            .sink { [weak self] _ in
                self?.updatePlaybackTime()
            }
            .store(in: &cancellables)
        
        playbackViewModel.$duration
            .sink { [weak self] _ in
                self?.updatePlaybackTime()
            }
            .store(in: &cancellables)
    }
    
    private func updateNowPlayingInfo(for track: Track?) {
        guard let track = track else {
            Task {
                await NowPlayingInfoManager.shared.clear()
            }
            return
        }
        
        let queueCount = playbackViewModel.queue.count
        let queueIndex = playbackViewModel.getCurrentQueueIndex()
        
        // Update track info through centralized manager
        Task {
            let _ = await NowPlayingInfoManager.shared.updateTrack(
                track: track,
                isPlaying: playbackViewModel.isPlaying,
                currentTime: playbackViewModel.currentTime,
                duration: playbackViewModel.duration,
                queueCount: queueCount,
                queueIndex: queueIndex
            )
            
            // Check if we need to load artwork
            let cachedArtwork = await NowPlayingInfoManager.shared.getCachedArtwork(trackId: track.id)
            if cachedArtwork == nil {
                // Load artwork asynchronously
                let requestId = await NowPlayingInfoManager.shared.getArtworkRequestId()
                let loadingTrackId = track.id
                
                if let artwork = await loadArtwork(for: track, requestId: requestId, trackId: loadingTrackId) {
                    // Update artwork through centralized manager
                    let applied = await NowPlayingInfoManager.shared.updateArtwork(
                        artwork: artwork,
                        trackId: loadingTrackId,
                        artworkRequestId: requestId
                    )
                    if !applied {
                        logger.debug("Artwork update rejected - track or request changed")
                    }
                }
            }
        }
    }
    
    private func updatePlaybackState(isPlaying: Bool) {
        let trackId = playbackViewModel.currentTrack?.id
        let currentTime = playbackViewModel.currentTime
        
        Task {
            let applied = await NowPlayingInfoManager.shared.updatePlaybackState(
                isPlaying: isPlaying,
                currentTime: currentTime,
                trackId: trackId
            )
            if !applied {
                // Track changed, trigger full update
                if let track = playbackViewModel.currentTrack {
                    updateNowPlayingInfo(for: track)
                }
            }
        }
    }
    
    private func updatePlaybackTime() {
        let trackId = playbackViewModel.currentTrack?.id
        let currentTime = playbackViewModel.currentTime
        let duration = playbackViewModel.duration
        
        Task {
            let applied = await NowPlayingInfoManager.shared.updatePlaybackTime(
                currentTime: currentTime,
                duration: duration,
                trackId: trackId
            )
            if !applied {
                // Track changed, ignore time update
            }
        }
    }
    
    private func loadArtwork(for track: Track, requestId: Int, trackId: String) async -> MPMediaItemArtwork? {
        // Check if request is still valid via centralized manager
        let currentTrackId = await NowPlayingInfoManager.shared.getCurrentTrackId()
        guard currentTrackId == trackId else { return nil }
        
        // Check cache first
        if let cached = await NowPlayingInfoManager.shared.getCachedArtwork(trackId: track.id) {
            return cached
        }
        
        let imageURL: URL? = {
            if let url = playbackViewModel.buildTrackImageURL(trackId: track.id, albumId: track.albumId) {
                return url
            }
            if let albumId = track.albumId,
               let url = playbackViewModel.albumArtURL(for: albumId) {
                return url
            }
            return nil
        }()
        
        guard let imageURL = imageURL else {
            return nil
        }
        
        return await loadArtwork(from: imageURL, requestId: requestId, trackId: trackId)
    }
    
    private func loadArtwork(from url: URL, requestId: Int, trackId: String) async -> MPMediaItemArtwork? {
        do {
            var request = URLRequest(url: url)
            request.cachePolicy = .returnCacheDataElseLoad
            request.timeoutInterval = 10.0
            
            let (data, response) = try await URLSession.shared.data(for: request)
            
            // Check if request is still valid before processing
            let currentTrackId = await NowPlayingInfoManager.shared.getCurrentTrackId()
            guard currentTrackId == trackId else { return nil }
            
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
                return nil
            }
            
            guard let image = UIImage(data: data) else {
                return nil
            }
            
            // Final check before returning
            let finalTrackId = await NowPlayingInfoManager.shared.getCurrentTrackId()
            guard finalTrackId == trackId else { return nil }
            
            return MPMediaItemArtwork(boundsSize: image.size) { _ in
                return image
            }
        } catch {
            logger.error("Failed to load artwork: \(error.localizedDescription)")
            return nil
        }
    }
    
    private func createCustomButtons() {
        if let image = UIImage(systemName: "arrow.clockwise") {
            skipAhead10Button = CPNowPlayingImageButton(image: image) { [weak self] _ in
                Task { @MainActor [weak self] in
                    await self?.skipAhead10Percent()
                }
            }
        }
        
        if let image = UIImage(systemName: "shuffle") {
            shuffleButton = CPNowPlayingImageButton(image: image) { [weak self] button in
                Task { @MainActor [weak self] in
                    guard let self = self else { return }
                    self.playbackViewModel.toggleShuffle()
                    button.isSelected = self.playbackViewModel.isShuffleEnabled
                    self.updateNowPlayingButtons()
                }
            }
            shuffleButton?.isSelected = playbackViewModel.isShuffleEnabled
        }
        
        let repeatImageName = (playbackViewModel.repeatMode == .one) ? "repeat.1" : "repeat"
        if let image = UIImage(systemName: repeatImageName) {
            repeatButton = CPNowPlayingImageButton(image: image) { [weak self] button in
                Task { @MainActor [weak self] in
                    guard let self = self else { return }
                    self.playbackViewModel.toggleRepeat()
                    let newMode = self.playbackViewModel.repeatMode
                    
                    let imageName = (newMode == .one) ? "repeat.1" : "repeat"
                    if let newImage = UIImage(systemName: imageName) {
                        self.updateRepeatButtonImage(newImage, for: newMode)
                    }
                    
                    button.isSelected = (newMode != .off)
                }
            }
            repeatButton?.isSelected = (playbackViewModel.repeatMode != .off)
        }
        
        if let image = UIImage(systemName: "heart") {
            heartButton = CPNowPlayingImageButton(image: image) { [weak self] _ in
                Task { @MainActor [weak self] in
                    await self?.toggleFavourite()
                }
            }
        }
        updateHeartButton(for: playbackViewModel.currentTrack)
        
        if let image = UIImage(systemName: "radio") {
            radioButton = CPNowPlayingImageButton(image: image) { [weak self] _ in
                Task { @MainActor [weak self] in
                    await self?.startRadio()
                }
            }
        }
    }
    
    private func updateNowPlayingButtons() {
        var buttons: [CPNowPlayingButton] = []
        if let skipAhead = skipAhead10Button { buttons.append(skipAhead) }
        if let shuffle = shuffleButton { buttons.append(shuffle) }
        if let repeatBtn = repeatButton { buttons.append(repeatBtn) }
        if let heart = heartButton { buttons.append(heart) }
        if let radio = radioButton { buttons.append(radio) }
        CPNowPlayingTemplate.shared.updateNowPlayingButtons(buttons)
    }
    
    private func updateRepeatButtonImage(_ image: UIImage, for mode: RepeatMode) {
        let imageName = (mode == .one) ? "repeat.1" : "repeat"
        if let newImage = UIImage(systemName: imageName) {
            self.repeatButton = CPNowPlayingImageButton(image: newImage) { [weak self] button in
                Task { @MainActor [weak self] in
                    guard let self = self else { return }
                    self.playbackViewModel.toggleRepeat()
                    let newMode = self.playbackViewModel.repeatMode
                    
                    let iconName = (newMode == .one) ? "repeat.1" : "repeat"
                    if let icon = UIImage(systemName: iconName) {
                        self.updateRepeatButtonImage(icon, for: newMode)
                    }
                    
                    button.isSelected = (newMode != .off)
                }
            }
            self.repeatButton?.isSelected = (mode != .off)
            updateNowPlayingButtons()
        }
    }
    
    private func updateHeartButton(for track: Track?) {
        let imageName = track?.isLiked == true ? "heart.fill" : "heart"
        guard let image = UIImage(systemName: imageName) else { return }
        
        heartButton = CPNowPlayingImageButton(image: image) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.toggleFavourite()
            }
        }
        
        updateNowPlayingButtons()
    }
    
    private func toggleFavourite() async {
        guard let track = playbackViewModel.currentTrack else { return }
        
        // Optimistic update
        let newLikedState = !track.isLiked
        FavoritesStore.shared.setLiked(track.id, newLikedState)
        
        // Create updated track with new liked state
        let updatedTrack = Track(
            id: track.id,
            title: track.title,
            albumId: track.albumId,
            albumTitle: track.albumTitle,
            artistName: track.artistName,
            duration: track.duration,
            trackNumber: track.trackNumber,
            discNumber: track.discNumber,
            dateAdded: track.dateAdded,
            playCount: track.playCount,
            isLiked: newLikedState,
            streamUrl: track.streamUrl,
            serverId: track.serverId
        )
        playbackViewModel.currentTrack = updatedTrack
        
        do {
            let serverUpdatedTrack = try await playbackRepository.toggleLike(track: track)
            
            // Reconcile with server state
            await MainActor.run {
                FavoritesStore.shared.updateAfterAPICall(trackId: serverUpdatedTrack.id, isLiked: serverUpdatedTrack.isLiked, serverId: serverUpdatedTrack.serverId)
                
                if playbackViewModel.currentTrack?.id == serverUpdatedTrack.id {
                    playbackViewModel.currentTrack = serverUpdatedTrack
                }
            }
            
            await updateLikedPlaylist(track: serverUpdatedTrack, isNowLiked: serverUpdatedTrack.isLiked)
        } catch {
            logger.error("Failed to toggle favourite: \(error.localizedDescription)")
            // Revert optimistic update
            await MainActor.run {
                FavoritesStore.shared.setLiked(track.id, !newLikedState)
                // Revert to original track state
                let revertedTrack = Track(
                    id: track.id,
                    title: track.title,
                    albumId: track.albumId,
                    albumTitle: track.albumTitle,
                    artistName: track.artistName,
                    duration: track.duration,
                    trackNumber: track.trackNumber,
                    discNumber: track.discNumber,
                    dateAdded: track.dateAdded,
                    playCount: track.playCount,
                    isLiked: !newLikedState,
                    streamUrl: track.streamUrl,
                    serverId: track.serverId
                )
                playbackViewModel.currentTrack = revertedTrack
            }
        }
    }
    
    private func updateLikedPlaylist(track: Track, isNowLiked: Bool) async {
        guard let libraryRepository = libraryRepository else {
            return
        }
        
        let manager = LikedPlaylistManager(
            libraryRepository: libraryRepository,
            coreDataStack: CoreDataStack.shared,
            serverId: track.serverId
        )
        
        do {
            if isNowLiked {
                try await manager.addTrackToLikedPlaylist(trackId: track.id)
            } else {
                try await manager.removeTrackFromLikedPlaylist(trackId: track.id)
            }
        } catch {
            logger.warning("Failed to update liked playlist: \(error.localizedDescription)")
        }
    }
    
    private func skipAhead10Percent() async {
        guard playbackViewModel.currentTrack != nil else { return }
        
        let currentTime = playbackViewModel.currentTime
        let duration = playbackViewModel.duration
        
        guard duration > 0 else { return }
        
        let skipAmount = duration * 0.1
        let newTime = min(currentTime + skipAmount, duration)
        playbackViewModel.seek(to: newTime)
    }
    
    private func startRadio() async {
        guard let track = playbackViewModel.currentTrack else { return }
        
        // Use the centralized startInstantMix method to ensure single actor and prevent duplicate queues
        playbackViewModel.startInstantMix(
            from: track.id,
            kind: .song,
            serverId: track.serverId
        )
    }
}


