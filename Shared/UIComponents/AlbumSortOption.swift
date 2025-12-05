
import Foundation

enum AlbumSortOption: String, SortOption {
    case title
    case artist
    case year
    
    var displayName: String {
        switch self {
        case .title: return "Title"
        case .artist: return "Artist"
        case .year: return "Year"
        }
    }
}

