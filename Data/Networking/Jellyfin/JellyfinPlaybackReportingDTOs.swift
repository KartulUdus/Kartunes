
import Foundation

// MARK: - Playback Reporting DTOs

struct JellyfinClientCapabilities: Encodable {
    let playableMediaTypes: [String]
    let supportsMediaControl: Bool
    let supportsSync: Bool
    let supportsPersistentIdentifier: Bool
    
    enum CodingKeys: String, CodingKey {
        case playableMediaTypes = "PlayableMediaTypes"
        case supportsMediaControl = "SupportsMediaControl"
        case supportsSync = "SupportsSync"
        case supportsPersistentIdentifier = "SupportsPersistentIdentifier"
    }
}

struct JellyfinPlaybackStartInfo: Encodable {
    let itemId: String
    let mediaSourceId: String?
    let playSessionId: String
    let positionTicks: Int64
    let isPaused: Bool
    let canSeek: Bool
    let playMethod: String
    
    enum CodingKeys: String, CodingKey {
        case itemId = "ItemId"
        case mediaSourceId = "MediaSourceId"
        case playSessionId = "PlaySessionId"
        case positionTicks = "PositionTicks"
        case isPaused = "IsPaused"
        case canSeek = "CanSeek"
        case playMethod = "PlayMethod"
    }
}

struct JellyfinPlaybackProgressInfo: Encodable {
    let itemId: String
    let mediaSourceId: String?
    let playSessionId: String
    let positionTicks: Int64
    let isPaused: Bool
    let playbackRate: Double
    let eventName: String?
    
    enum CodingKeys: String, CodingKey {
        case itemId = "ItemId"
        case mediaSourceId = "MediaSourceId"
        case playSessionId = "PlaySessionId"
        case positionTicks = "PositionTicks"
        case isPaused = "IsPaused"
        case playbackRate = "PlaybackRate"
        case eventName = "EventName"
    }
}

struct JellyfinPlaybackStopInfo: Encodable {
    let itemId: String
    let mediaSourceId: String?
    let playSessionId: String
    let positionTicks: Int64
    let nextMediaType: String?
    
    enum CodingKeys: String, CodingKey {
        case itemId = "ItemId"
        case mediaSourceId = "MediaSourceId"
        case playSessionId = "PlaySessionId"
        case positionTicks = "PositionTicks"
        case nextMediaType = "NextMediaType"
    }
}

