//
//  WatchPlaybackSession.swift
//  Kartunes Watch App
//
//  Created on [Date]
//

import Foundation
import WatchConnectivity
import OSLog

/// Manages WatchConnectivity communication on the watchOS side
@MainActor
final class WatchPlaybackSession: NSObject {
    private let logger = Logger(subsystem: "com.kartunes.app", category: "Watch")
    
    private var session: WCSession?
    weak var viewModel: WatchPlaybackViewModel?
    
    override init() {
        super.init()
        setupWatchConnectivity()
    }
    
    private func setupWatchConnectivity() {
        guard WCSession.isSupported() else {
            logger.warning("WatchConnectivity not supported")
            return
        }
        
        session = WCSession.default
        session?.delegate = self
        session?.activate()
    }
    
    // MARK: - Command Sending
    
    func sendPlayPause() {
        sendCommand(.playPause)
    }
    
    func sendNext() {
        sendCommand(.next)
    }
    
    func sendPrevious() {
        sendCommand(.previous)
    }
    
    func sendSeek(to time: TimeInterval) {
        sendCommand(.seek, seekTime: time)
    }
    
    func sendToggleFavourite() {
        sendCommand(.toggleFavourite)
    }
    
    func sendRadioFromCurrentTrack() {
        sendCommand(.radioFromCurrentTrack)
    }
    
    func requestState() {
        guard let session = session else { return }
        
        // Always try application context first (works even when not reachable)
        let context = session.receivedApplicationContext
        if !context.isEmpty,
           let state = decodeState(from: context) {
            viewModel?.updateState(state)
        }
        
        // If reachable, also send a message request
        guard session.isReachable else { return }
        
        let request = WatchRequestStateMessage(type: .requestState)
        
        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(request)
            let message = try JSONSerialization.jsonObject(with: data) as! [String: Any]
            
            session.sendMessage(message) { [weak self] reply in
                Task { @MainActor [weak self] in
                    guard !reply.isEmpty, let state = self?.decodeState(from: reply) else {
                        return
                    }
                    self?.viewModel?.updateState(state)
                }
            }
        } catch {
            logger.error("Failed to encode request: \(error.localizedDescription)")
        }
    }
    
    private func sendCommand(_ command: WatchCommand, seekTime: TimeInterval? = nil) {
        guard let session = session else { return }
        
        let message = WatchCommandMessage(type: .command, command: command, seekTime: seekTime)
        
        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(message)
            let messageDict = try JSONSerialization.jsonObject(with: data) as! [String: Any]
            
            if session.isReachable {
                session.sendMessage(messageDict, replyHandler: nil) { [weak self] error in
                    self?.logger.warning("Failed to send command: \(error.localizedDescription)")
                    // Request state update after command to sync UI
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 200_000_000) // 0.2 seconds
                        self?.requestState()
                    }
                }
            } else {
                // Update application context for background delivery
                try? session.updateApplicationContext(messageDict)
            }
        } catch {
            logger.error("Failed to encode command: \(error.localizedDescription)")
        }
    }
    
    private func decodeState(from dict: [String: Any]) -> WatchStateMessage? {
        guard !dict.isEmpty,
              let typeString = dict["type"] as? String,
              typeString == WatchMessageType.state.rawValue,
              let jsonData = try? JSONSerialization.data(withJSONObject: dict) else {
            return nil
        }
        
        do {
            let decoder = JSONDecoder()
            return try decoder.decode(WatchStateMessage.self, from: jsonData)
        } catch {
            logger.error("Failed to decode state: \(error.localizedDescription)")
            return nil
        }
    }
}

// MARK: - WCSessionDelegate

extension WatchPlaybackSession: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        Task { @MainActor in
            if let error = error {
                self.logger.warning("Activation failed: \(error.localizedDescription)")
            } else {
                requestState()
            }
        }
    }
    
    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in
            if session.isReachable {
                requestState()
            }
        }
    }
    
    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        Task { @MainActor in
            if let state = decodeState(from: message) {
                viewModel?.updateState(state)
            }
        }
    }
    
    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        Task { @MainActor in
            if let state = decodeState(from: applicationContext) {
                viewModel?.updateState(state)
            }
        }
    }
}

