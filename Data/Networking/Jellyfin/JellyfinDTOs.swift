
import Foundation

// MARK: - DTOs (Data Transfer Objects)

struct JellyfinLibraryDTO: Decodable {
    let id: String
    let name: String
    
    enum CodingKeys: String, CodingKey {
        case id = "Id"
        case name = "Name"
    }
}

struct JellyfinArtistDTO: Decodable {
    let id: String
    let name: String
    let imageTags: [String: String]?
    
    enum CodingKeys: String, CodingKey {
        case id = "Id"
        case name = "Name"
        case imageTags = "ImageTags"
    }
}

struct JellyfinAlbumDTO: Decodable {
    let id: String
    let name: String
    let artistName: String?
    let productionYear: Int?
    let imageTags: [String: String]?
    
    enum CodingKeys: String, CodingKey {
        case id = "Id"
        case name = "Name"
        case artistName = "AlbumArtist"
        case productionYear = "ProductionYear"
        case imageTags = "ImageTags"
    }
}

struct JellyfinTrackDTO: Decodable {
    let id: String
    let name: String
    let albumId: String?
    let album: String?
    let artists: [String]?
    let genres: [String]?
    let runTimeTicks: Int64?
    let indexNumber: Int?
    let discNumber: Int?
    let dateAdded: String?
    let playCount: Int?
    let container: String?
    let userData: JellyfinUserDataDTO?
    let playlistItemId: String? // Entry ID for playlist items (used for removal)
    
    enum CodingKeys: String, CodingKey {
        case id = "Id"
        case name = "Name"
        case albumId = "AlbumId"
        case album = "Album"
        case artists = "Artists"
        case genres = "Genres"
        case runTimeTicks = "RunTimeTicks"
        case indexNumber = "IndexNumber"
        case discNumber = "DiscNumber"
        case dateAdded = "DateCreated"
        case playCount = "PlayCount"
        case container = "Container"
        case userData = "UserData"
        case playlistItemId = "PlaylistItemId"
    }
}

struct JellyfinUserDataDTO: Decodable {
    let isFavorite: Bool?
    
    enum CodingKeys: String, CodingKey {
        case isFavorite = "IsFavorite"
    }
}

struct JellyfinPlaylistDTO: Decodable {
    let id: String
    let name: String
    let summary: String?
    let isFolder: Bool?
    let path: String? // For detecting file-based playlists (.m3u, .m3u8)
    let locationType: String? // "FileSystem" for file-based, "Virtual" for server-managed
    let ownerUserId: String?
    
    /// Determines if this is a file-based playlist (read-only)
    /// - Parameter serverType: The type of media server (Jellyfin or Emby)
    /// - Returns: true if the playlist is file-based and read-only
    func isFileBased(serverType: MediaServerType) -> Bool {
        switch serverType {
        case .jellyfin:
            // Jellyfin logic: File-based if path ends with .m3u/.m3u8 OR LocationType=FileSystem
            if let path = path {
                let lowercased = path.lowercased()
                return lowercased.hasSuffix(".m3u") || lowercased.hasSuffix(".m3u8")
            }
            // If no path, check LocationType
            return locationType == "FileSystem"
            
        case .emby:
            // Emby logic: ALL playlists are editable unless they're user-placed files in media library
            // Emby stores virtual playlists in /config/data/playlists/ - these are editable
            // Only .m3u files in the user's media library folder are read-only
            if let path = path?.lowercased() {
                // Check if path is in Emby's config folder (editable virtual playlists)
                let isInConfigFolder = path.contains("/config/data/playlists/") || 
                                       path.contains("/config/playlists/") ||
                                       path.contains("data/playlists/") ||
                                       path.contains("playlists/") && !path.contains("/media/")
                
                // If it's in config folder, it's editable (not file-based)
                if isInConfigFolder {
                    return false
                }
                
                // Check if path is in user's media library (user-placed .m3u files are read-only)
                // Common media library patterns: /media/, /mnt/, /volume/, /music/, /audio/
                let isInMediaLibrary = path.contains("/media/") || 
                                      path.contains("/mnt/") ||
                                      path.contains("/volume/") ||
                                      path.contains("/music/") ||
                                      path.contains("/audio/") ||
                                      path.contains("/home/") && (path.hasSuffix(".m3u") || path.hasSuffix(".m3u8"))
                
                // If in media library AND has .m3u extension, it's a user file (read-only)
                if isInMediaLibrary && (path.hasSuffix(".m3u") || path.hasSuffix(".m3u8")) {
                    return true
                }
                
                // Default: assume editable (Emby playlists are editable by default)
                return false
            }
            
            // If no path, assume editable (Emby virtual playlists may not have paths)
            // LocationType is unreliable for Emby, so we default to editable
            return false
        }
    }
    
    enum CodingKeys: String, CodingKey {
        case id = "Id"
        case name = "Name"
        case summary = "Overview"
        case isFolder = "IsFolder"
        case path = "Path"
        case locationType = "LocationType"
        case ownerUserId = "OwnerId"
    }
}

struct JellyfinBaseItemQueryResult: Decodable {
    let items: [JellyfinBaseItemDTO]
    let totalRecordCount: Int
    
    enum CodingKeys: String, CodingKey {
        case items = "Items"
        case totalRecordCount = "TotalRecordCount"
    }
}

struct JellyfinBaseItemDTO: Decodable {
    let id: String
    let name: String
    let type: String?
    let albumId: String?
    let album: String?
    let albumArtist: String?
    let artists: [String]?
    let genres: [String]?
    let runTimeTicks: Int64?
    let indexNumber: Int?
    let discNumber: Int?
    let productionYear: Int?
    let dateAdded: String?
    let playCount: Int?
    let container: String?
    let imageTags: [String: String]?
    let userData: JellyfinUserDataDTO?
    let path: String?
    let locationType: String?
    let overview: String?
    let isFolder: Bool?
    let playlistItemId: String?
    
    enum CodingKeys: String, CodingKey {
        case id = "Id"
        case name = "Name"
        case type = "Type"
        case albumId = "AlbumId"
        case album = "Album"
        case albumArtist = "AlbumArtist"
        case artists = "Artists"
        case genres = "Genres"
        case runTimeTicks = "RunTimeTicks"
        case indexNumber = "IndexNumber"
        case discNumber = "DiscNumber"
        case productionYear = "ProductionYear"
        case dateAdded = "DateCreated"
        case playCount = "PlayCount"
        case container = "Container"
        case imageTags = "ImageTags"
        case userData = "UserData"
        case path = "Path"
        case locationType = "LocationType"
        case overview = "Overview"
        case isFolder = "IsFolder"
        case playlistItemId = "PlaylistItemId"
    }
}

struct JellyfinAuthenticateRequest: Encodable {
    let username: String
    let password: String
    
    enum CodingKeys: String, CodingKey {
        case username = "Username"
        case password = "Pw"
    }
}

struct JellyfinAuthenticationResult: Decodable {
    let user: JellyfinUserDTO?
    let accessToken: String?
    let serverId: String?
    
    enum CodingKeys: String, CodingKey {
        case user = "User"
        case accessToken = "AccessToken"
        case serverId = "ServerId"
    }
}

struct JellyfinUserDTO: Decodable {
    let id: String
    
    enum CodingKeys: String, CodingKey {
        case id = "Id"
    }
}

struct JellyfinVirtualFolderInfo: Decodable {
    let name: String
    let itemId: String?
    
    enum CodingKeys: String, CodingKey {
        case name = "Name"
        case itemId = "ItemId"
    }
}

struct JellyfinUserItemDataResponse: Decodable {
    let isFavorite: Bool?
    
    enum CodingKeys: String, CodingKey {
        case isFavorite = "IsFavorite"
    }
}

struct JellyfinPlaybackInfo: Decodable {
    let mediaSources: [JellyfinMediaSourceInfo]?
    let playSessionId: String?
    
    enum CodingKeys: String, CodingKey {
        case mediaSources = "MediaSources"
        case playSessionId = "PlaySessionId"
    }
}

struct JellyfinMediaSourceInfo: Decodable {
    let id: String?
    let supportsDirectStream: Bool?
    let supportsDirectPlay: Bool?
    let container: String?
    
    enum CodingKeys: String, CodingKey {
        case id = "Id"
        case supportsDirectStream = "SupportsDirectStream"
        case supportsDirectPlay = "SupportsDirectPlay"
        case container = "Container"
    }
}

// Empty response for 204 No Content responses
struct EmptyResponse: Decodable {}

