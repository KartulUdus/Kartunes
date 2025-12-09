
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
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }
        
        let existingInfo = MPNowPlayingInfoCenter.default().nowPlayingInfo
        let existingTitle = existingInfo?[MPMediaItemPropertyTitle] as? String
        let existingArtist = existingInfo?[MPMediaItemPropertyArtist] as? String
        let isSameTrack = existingTitle == track.title && existingArtist == track.artistName
        
        var nowPlayingInfo: [String: Any] = [
            MPMediaItemPropertyTitle: track.title,
            MPMediaItemPropertyArtist: track.artistName,
            MPNowPlayingInfoPropertyPlaybackRate: playbackViewModel.isPlaying ? 1.0 : 0.0
        ]
        
        if let albumTitle = track.albumTitle {
            nowPlayingInfo[MPMediaItemPropertyAlbumTitle] = albumTitle
        }
        
        if playbackViewModel.duration > 0 {
            nowPlayingInfo[MPMediaItemPropertyPlaybackDuration] = playbackViewModel.duration
        }
        
        nowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = playbackViewModel.currentTime
        
        if isSameTrack, let existingArtwork = existingInfo?[MPMediaItemPropertyArtwork] as? MPMediaItemArtwork {
            nowPlayingInfo[MPMediaItemPropertyArtwork] = existingArtwork
        }
        
        if !isSameTrack || existingInfo?[MPMediaItemPropertyArtwork] == nil {
            Task {
                if let artwork = await loadArtwork(for: track) {
                    await MainActor.run {
                        var updatedInfo = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
                        updatedInfo[MPMediaItemPropertyArtwork] = artwork
                        updatedInfo[MPMediaItemPropertyTitle] = track.title
                        updatedInfo[MPMediaItemPropertyArtist] = track.artistName
                        if let albumTitle = track.albumTitle {
                            updatedInfo[MPMediaItemPropertyAlbumTitle] = albumTitle
                        }
                        MPNowPlayingInfoCenter.default().nowPlayingInfo = updatedInfo
                    }
                }
            }
        }
        
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
    }
    
    private func updatePlaybackState(isPlaying: Bool) {
        var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
        info[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? 1.0 : 0.0
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }
    
    private func updatePlaybackTime() {
        var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = playbackViewModel.currentTime
        if playbackViewModel.duration > 0 {
            info[MPMediaItemPropertyPlaybackDuration] = playbackViewModel.duration
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }
    
    private func loadArtwork(for track: Track) async -> MPMediaItemArtwork? {
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
        
        return await loadArtwork(from: imageURL)
    }
    
    private func loadArtwork(from url: URL) async -> MPMediaItemArtwork? {
        do {
            var request = URLRequest(url: url)
            request.cachePolicy = .returnCacheDataElseLoad
            request.timeoutInterval = 10.0
            
            let (data, response) = try await URLSession.shared.data(for: request)
            
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
                return nil
            }
            
            guard let image = UIImage(data: data) else {
                return nil
            }
            
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
        
        do {
            let updatedTrack = try await playbackRepository.toggleLike(track: track)
            if playbackViewModel.currentTrack?.id == updatedTrack.id {
                playbackViewModel.currentTrack = updatedTrack
            }
            await updateLikedPlaylist(track: updatedTrack, isNowLiked: updatedTrack.isLiked)
        } catch {
            logger.error("Failed to toggle favourite: \(error.localizedDescription)")
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
        
        do {
            let tracks = try await playbackRepository.generateInstantMix(
                from: track.id,
                kind: .song,
                serverId: track.serverId
            )
            
            guard !tracks.isEmpty else { return }
            
            // Replace queue and start playing
            playbackViewModel.startQueue(from: tracks, at: 0, context: .instantMix(seedItemId: track.id))
        } catch {
            logger.error("Failed to start radio: \(error.localizedDescription)")
        }
    }
}


