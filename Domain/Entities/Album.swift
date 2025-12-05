
import Foundation

struct Album: Identifiable, Hashable {
    let id: String
    let title: String
    let artistName: String
    let thumbnailURL: URL?
    let year: Int?
}

