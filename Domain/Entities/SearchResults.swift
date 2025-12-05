
import Foundation

struct SearchResults {
    let tracks: [Track]
    let albums: [Album]
    let artists: [Artist]
    
    var isEmpty: Bool {
        tracks.isEmpty && albums.isEmpty && artists.isEmpty
    }
}

