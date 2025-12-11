
import Foundation
import WatchConnectivity
import Combine
import CoreData

/// Manages WatchConnectivity communication between iPhone and Apple Watch
/// Note: This service is iOS-only and requires WatchConnectivity framework to be linked
@MainActor
final class WatchConnectivityService: NSObject, ObservableObject {
    private let logger = Log.make(.watch)
    
    private var session: WCSession?
    private let playbackViewModel: PlaybackViewModel
    private let playbackRepository: PlaybackRepository
    private let apiClient: MediaServerAPIClient?
    private let coreDataStack: CoreDataStack?
    private var cancellables = Set<AnyCancellable>()
    private var lastSentState: WatchStateMessage?
    private let positionDeltaThreshold: TimeInterval = 5
    
    init(
        playbackViewModel: PlaybackViewModel,
        playbackRepository: PlaybackRepository,
        apiClient: MediaServerAPIClient? = nil,
        coreDataStack: CoreDataStack? = nil
    ) {
        self.playbackViewModel = playbackViewModel
        self.playbackRepository = playbackRepository
        self.apiClient = apiClient
        self.coreDataStack = coreDataStack ?? CoreDataStack.shared
        super.init()
        
        setupWatchConnectivity()
        setupObservers()
    }
    
    // MARK: - Setup
    
    private func setupWatchConnectivity() {
        guard WCSession.isSupported() else {
            logger.warning("WatchConnectivity not supported")
            return
        }
        
        session = WCSession.default
        session?.delegate = self
        session?.activate()
    }
    
    private func setupObservers() {
        // Observe track changes
        playbackViewModel.$currentTrack
            .removeDuplicates()
            .sink { [weak self] _ in
                self?.sendStateUpdate()
            }
            .store(in: &cancellables)
        
        // Observe playback state changes
        playbackViewModel.$isPlaying
            .removeDuplicates()
            .sink { [weak self] _ in
                self?.sendStateUpdate()
            }
            .store(in: &cancellables)
        
        // Observe time changes (throttled to avoid spamming)
        playbackViewModel.$currentTime
            .throttle(for: .seconds(2), scheduler: DispatchQueue.main, latest: true)
            .sink { [weak self] _ in
                self?.sendStateUpdate()
            }
            .store(in: &cancellables)
        
        // Observe duration changes
        playbackViewModel.$duration
            .removeDuplicates()
            .sink { [weak self] _ in
                self?.sendStateUpdate()
            }
            .store(in: &cancellables)
    }
    
    // MARK: - State Updates
    
    private func sendStateUpdate() {
        guard let session = session else {
            return
        }
        
        // Always update application context (works even when not reachable)
        // This ensures the watch can get state even if it's not actively connected
        
        let trackSummary: TrackSummary?
        if let track = playbackViewModel.currentTrack {
            trackSummary = TrackSummary(from: track, apiClient: apiClient, coreDataStack: coreDataStack)
        } else {
            trackSummary = nil
        }
        
        let playbackState: PlaybackState = playbackViewModel.isPlaying ? .playing : .paused
        
        let stateMessage = WatchStateMessage(
            type: .state,
            track: trackSummary,
            playbackState: playbackState,
            position: playbackViewModel.currentTime,
            duration: playbackViewModel.duration
        )
        
        // Only send if state actually changed (to avoid unnecessary updates)
        // Always send if track changed (for album art updates)
        if let lastState = lastSentState {
            let trackSummaryChanged: Bool = {
                switch (lastState.track, stateMessage.track) {
                case (.none, .none):
                    return false
                case (.some(let previous), .some(let current)):
                    return previous.id != current.id
                        || previous.title != current.title
                        || previous.artist != current.artist
                        || previous.albumArtURL != current.albumArtURL
                        || previous.isFavourite != current.isFavourite
                default:
                    return true
                }
            }()

            let playbackUnchanged = lastState.playbackState == stateMessage.playbackState
            let positionDelta = abs(lastState.position - stateMessage.position)
            if !trackSummaryChanged && playbackUnchanged && positionDelta < positionDeltaThreshold {
                return
            }
        }

        lastSentState = stateMessage
        
        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(stateMessage)
            let message = try JSONSerialization.jsonObject(with: data) as! [String: Any]
            
            // Always update application context (works even when watch isn't reachable)
            // But only if the device is paired
            if session.isPaired {
                try? session.updateApplicationContext(message)
            }
            
            // If reachable, also send immediate message
            if session.isReachable {
                session.sendMessage(message, replyHandler: nil) { error in
                    self.logger.warning("Failed to send state message: \(error.localizedDescription)")
                }
            }
        } catch {
            logger.error("Failed to encode state message: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Command Handling
    
    private func handleCommand(_ command: WatchCommand, seekTime: TimeInterval? = nil) {
        logger.debug("Received command: \(command.rawValue)")
        
        switch command {
        case .playPause:
            playbackViewModel.togglePlayPause()
            // Force immediate state update after toggle
            Task {
                try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
                sendStateUpdate()
            }
            
        case .next:
            playbackViewModel.next()
            
        case .previous:
            playbackViewModel.previous()
            
        case .seek:
            if let time = seekTime {
                playbackViewModel.seek(to: time)
            }
            
        case .toggleFavourite:
            playbackViewModel.toggleLike()
            
        case .radioFromCurrentTrack:
            guard let track = playbackViewModel.currentTrack else {
                logger.warning("No current track for radio")
                return
            }
            playbackViewModel.startInstantMix(from: track.id)
        }
    }
}

// MARK: - WCSessionDelegate

extension WatchConnectivityService: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        Task { @MainActor in
            if let error = error {
                self.logger.warning("Activation failed: \(error.localizedDescription)")
            } else {
                sendStateUpdate()
            }
        }
    }
    
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {
        Task { @MainActor in
            self.logger.debug("Session became inactive")
        }
    }
    
    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        Task { @MainActor in
            self.logger.debug("Session deactivated, reactivating...")
            session.activate()
        }
    }
    
    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in
            sendStateUpdate()
        }
    }
    
    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        Task { @MainActor in
            handleReceivedMessage(message)
        }
    }
    
    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        Task { @MainActor in
            // Handle the message first
            handleReceivedMessage(message)
            
            // Always reply with current state (even if message wasn't requestState)
            let trackSummary: TrackSummary?
            if let track = playbackViewModel.currentTrack {
                trackSummary = TrackSummary(from: track, apiClient: apiClient)
            } else {
                trackSummary = nil
            }
            
            let playbackState: PlaybackState = playbackViewModel.isPlaying ? .playing : .paused
            
            let stateMessage = WatchStateMessage(
                type: .state,
                track: trackSummary,
                playbackState: playbackState,
                position: playbackViewModel.currentTime,
                duration: playbackViewModel.duration
            )
            
            do {
                let encoder = JSONEncoder()
                let data = try encoder.encode(stateMessage)
                let reply = try JSONSerialization.jsonObject(with: data) as! [String: Any]
                replyHandler(reply)
            } catch {
                self.logger.error("Failed to encode reply: \(error.localizedDescription)")
                replyHandler([:])
            }
        }
    }
    
    private func handleReceivedMessage(_ message: [String: Any]) {
        guard let typeString = message["type"] as? String,
              let type = WatchMessageType(rawValue: typeString) else {
            logger.warning("Invalid message type")
            return
        }
        
        switch type {
        case .command:
            guard let commandString = message["command"] as? String,
                  let command = WatchCommand(rawValue: commandString) else {
                logger.warning("Invalid command")
                return
            }
            let seekTime = message["seekTime"] as? TimeInterval
            handleCommand(command, seekTime: seekTime)
            
        case .requestState:
            sendStateUpdate()
            
        case .state:
            // State messages are sent from iPhone to Watch, not received
            break
        }
    }
}
