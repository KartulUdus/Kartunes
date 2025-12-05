
import CarPlay
import MediaPlayer
import Combine
import UIKit

@MainActor
final class CarPlayNowPlayingCoordinator {
    private let logger = Log.make(.carPlay)
    
    private let playbackViewModel: PlaybackViewModel
    private let playbackRepository: PlaybackRepository
    private var cancellables = Set<AnyCancellable>()
    
    // Custom buttons
    private var back10PercentButton: CPNowPlayingButton?
    private var forward10PercentButton: CPNowPlayingButton?
    private var back30sButton: CPNowPlayingButton?
    private var forward30sButton: CPNowPlayingButton?
    private var heartButton: CPNowPlayingButton?
    private var radioButton: CPNowPlayingButton?
    
    init(
        playbackViewModel: PlaybackViewModel,
        playbackRepository: PlaybackRepository
    ) {
        self.playbackViewModel = playbackViewModel
        self.playbackRepository = playbackRepository
    }
    
    func updateRepositories(
        playbackViewModel: PlaybackViewModel,
        playbackRepository: PlaybackRepository
    ) {
        stop()
        self.playbackViewModel = playbackViewModel
        self.playbackRepository = playbackRepository
        start()
    }
    
    func start() {
        setupRemoteCommands()
        setupObservers()
        createCustomButtons()
        updateNowPlayingButtons()
    }
    
    func stop() {
        cancellables.removeAll()
        removeRemoteCommands()
    }
    
    // MARK: - Remote Commands
    
    private func setupRemoteCommands() {
        let commandCenter = MPRemoteCommandCenter.shared()
        
        // Play
        commandCenter.playCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.playbackRepository.resume()
                self?.playbackViewModel.isPlaying = true
            }
            return .success
        }
        
        // Pause
        commandCenter.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.playbackRepository.pause()
                self?.playbackViewModel.isPlaying = false
            }
            return .success
        }
        
        // Toggle Play/Pause
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
        
        // Next Track
        commandCenter.nextTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.playbackRepository.next()
            }
            return .success
        }
        
        // Previous Track
        commandCenter.previousTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.playbackRepository.previous()
            }
            return .success
        }
        
        // Skip Forward (30s)
        commandCenter.skipForwardCommand.preferredIntervals = [30]
        commandCenter.skipForwardCommand.addTarget { [weak self] event in
            guard let event = event as? MPSkipIntervalCommandEvent else { return .commandFailed }
            Task { @MainActor [weak self] in
                await self?.seekForward(seconds: event.interval)
            }
            return .success
        }
        
        // Skip Backward (30s)
        commandCenter.skipBackwardCommand.preferredIntervals = [30]
        commandCenter.skipBackwardCommand.addTarget { [weak self] event in
            guard let event = event as? MPSkipIntervalCommandEvent else { return .commandFailed }
            Task { @MainActor [weak self] in
                await self?.seekBackward(seconds: event.interval)
            }
            return .success
        }
        
        // Change Playback Position (for scrubbing)
        commandCenter.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            Task { @MainActor [weak self] in
                await self?.playbackRepository.seek(to: event.positionTime)
            }
            return .success
        }
        
        // Enable all commands
        commandCenter.playCommand.isEnabled = true
        commandCenter.pauseCommand.isEnabled = true
        commandCenter.togglePlayPauseCommand.isEnabled = true
        commandCenter.nextTrackCommand.isEnabled = true
        commandCenter.previousTrackCommand.isEnabled = true
        commandCenter.skipForwardCommand.isEnabled = true
        commandCenter.skipBackwardCommand.isEnabled = true
        commandCenter.changePlaybackPositionCommand.isEnabled = true
    }
    
    private func removeRemoteCommands() {
        let commandCenter = MPRemoteCommandCenter.shared()
        commandCenter.playCommand.removeTarget(nil)
        commandCenter.pauseCommand.removeTarget(nil)
        commandCenter.togglePlayPauseCommand.removeTarget(nil)
        commandCenter.nextTrackCommand.removeTarget(nil)
        commandCenter.previousTrackCommand.removeTarget(nil)
        commandCenter.skipForwardCommand.removeTarget(nil)
        commandCenter.skipBackwardCommand.removeTarget(nil)
        commandCenter.changePlaybackPositionCommand.removeTarget(nil)
    }
    
    // MARK: - Observers
    
    private func setupObservers() {
        // Observe current track changes
        playbackViewModel.$currentTrack
            .sink { [weak self] track in
                self?.updateNowPlayingInfo(for: track)
                self?.updateHeartButton(for: track)
            }
            .store(in: &cancellables)
        
        // Observe playback state
        playbackViewModel.$isPlaying
            .sink { [weak self] isPlaying in
                self?.updatePlaybackState(isPlaying: isPlaying)
            }
            .store(in: &cancellables)
        
        // Observe time updates
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
    
    // MARK: - Now Playing Info
    
    private func updateNowPlayingInfo(for track: Track?) {
        guard let track = track else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }
        
        var nowPlayingInfo: [String: Any] = [
            MPMediaItemPropertyTitle: track.title,
            MPMediaItemPropertyArtist: track.artistName,
            MPNowPlayingInfoPropertyPlaybackRate: playbackViewModel.isPlaying ? 1.0 : 0.0
        ]
        
        if let albumTitle = track.albumTitle {
            nowPlayingInfo[MPMediaItemPropertyAlbumTitle] = albumTitle
        }
        
        // Update duration
        if playbackViewModel.duration > 0 {
            nowPlayingInfo[MPMediaItemPropertyPlaybackDuration] = playbackViewModel.duration
        }
        
        // Update elapsed time
        nowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = playbackViewModel.currentTime
        
        // Load artwork asynchronously
        Task {
            if let artwork = await loadArtwork(for: track) {
                await MainActor.run {
                    nowPlayingInfo[MPMediaItemPropertyArtwork] = artwork
                    MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
                }
            } else {
                await MainActor.run {
                    MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
                }
            }
        }
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
        // TODO: Load artwork from Jellyfin image endpoint
        // For now, return nil - will be implemented when we have image loading
        return nil
    }
    
    // MARK: - Custom Buttons
    
    private func createCustomButtons() {
        // Back 10%
        back10PercentButton = CPNowPlayingButton(
            handler: { [weak self] _ in
                Task { @MainActor [weak self] in
                    await self?.seekBackward(percentage: 0.1)
                }
            }
        )
        back10PercentButton?.image = UIImage(systemName: "gobackward.10")
        
        // Forward 10%
        forward10PercentButton = CPNowPlayingButton(
            handler: { [weak self] _ in
                Task { @MainActor [weak self] in
                    await self?.seekForward(percentage: 0.1)
                }
            }
        )
        forward10PercentButton?.image = UIImage(systemName: "goforward.10")
        
        // Back 30s
        back30sButton = CPNowPlayingButton(
            handler: { [weak self] _ in
                Task { @MainActor [weak self] in
                    await self?.seekBackward(seconds: 30)
                }
            }
        )
        back30sButton?.image = UIImage(systemName: "gobackward.30")
        
        // Forward 30s
        forward30sButton = CPNowPlayingButton(
            handler: { [weak self] _ in
                Task { @MainActor [weak self] in
                    await self?.seekForward(seconds: 30)
                }
            }
        )
        forward30sButton?.image = UIImage(systemName: "goforward.30")
        
        // Heart button (favourite)
        heartButton = CPNowPlayingButton(
            handler: { [weak self] _ in
                Task { @MainActor [weak self] in
                    await self?.toggleFavourite()
                }
            }
        )
        updateHeartButton(for: playbackViewModel.currentTrack)
        
        // Radio button (InstantMix)
        radioButton = CPNowPlayingButton(
            handler: { [weak self] _ in
                Task { @MainActor [weak self] in
                    await self?.startRadio()
                }
            }
        )
        radioButton?.image = UIImage(systemName: "radio")
    }
    
    private func updateNowPlayingButtons() {
        var buttons: [CPNowPlayingButton] = []
        
        if let back10Percent = back10PercentButton {
            buttons.append(back10Percent)
        }
        if let forward10Percent = forward10PercentButton {
            buttons.append(forward10Percent)
        }
        if let back30s = back30sButton {
            buttons.append(back30s)
        }
        if let forward30s = forward30sButton {
            buttons.append(forward30s)
        }
        if let heart = heartButton {
            buttons.append(heart)
        }
        if let radio = radioButton {
            buttons.append(radio)
        }
        
        CPNowPlayingTemplate.shared.updateNowPlayingButtons(buttons)
    }
    
    private func updateHeartButton(for track: Track?) {
        guard let track = track else {
            heartButton?.image = UIImage(systemName: "heart")
            return
        }
        
        let imageName = track.isLiked ? "heart.fill" : "heart"
        heartButton?.image = UIImage(systemName: imageName)
    }
    
    // MARK: - Seek Helpers
    
    private func seekForward(percentage: Double) async {
        let duration = playbackViewModel.duration
        guard duration > 0 else { return }
        
        let currentTime = playbackViewModel.currentTime
        let newTime = min(currentTime + (duration * percentage), duration)
        await playbackRepository.seek(to: newTime)
    }
    
    private func seekBackward(percentage: Double) async {
        let duration = playbackViewModel.duration
        guard duration > 0 else { return }
        
        let currentTime = playbackViewModel.currentTime
        let newTime = max(currentTime - (duration * percentage), 0)
        await playbackRepository.seek(to: newTime)
    }
    
    private func seekForward(seconds: TimeInterval) async {
        let duration = playbackViewModel.duration
        guard duration > 0 else { return }
        
        let currentTime = playbackViewModel.currentTime
        let newTime = min(currentTime + seconds, duration)
        await playbackRepository.seek(to: newTime)
    }
    
    private func seekBackward(seconds: TimeInterval) async {
        let duration = playbackViewModel.duration
        guard duration > 0 else { return }
        
        let currentTime = playbackViewModel.currentTime
        let newTime = max(currentTime - seconds, 0)
        await playbackRepository.seek(to: newTime)
    }
    
    // MARK: - Actions
    
    private func toggleFavourite() async {
        guard let track = playbackViewModel.currentTrack else { return }
        
        do {
            let updatedTrack = try await playbackRepository.toggleLike(track: track)
            // Update view model's track if it's still the current one
            if playbackViewModel.currentTrack?.id == updatedTrack.id {
                playbackViewModel.currentTrack = updatedTrack
            }
        } catch {
            logger.error("Failed to toggle favourite: \(error.localizedDescription)")
        }
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

