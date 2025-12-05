
import Foundation

enum TrackSortOption: String, SortOption {
    case title
    case artist
    case album
    case duration
    case dateAdded
    case trackNumber
    case discNumber
    case playCount
    
    var displayName: String {
        switch self {
        case .title: return "Title"
        case .artist: return "Artist"
        case .album: return "Album"
        case .duration: return "Duration"
        case .dateAdded: return "Date Added"
        case .trackNumber: return "Track Number"
        case .discNumber: return "Disc Number"
        case .playCount: return "Play Count"
        }
    }
}

