
import Foundation

enum ArtistSortOption: String, SortOption {
    case name
    
    var displayName: String {
        switch self {
        case .name: return "Name"
        }
    }
}

