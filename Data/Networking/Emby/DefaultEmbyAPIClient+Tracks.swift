
import Foundation

extension DefaultEmbyAPIClient {
    func fetchTracksImpl(byAlbumId: String?, byArtistId: String?) async throws -> [JellyfinTrackDTO] {
        if byAlbumId != nil || byArtistId != nil {
            var components = URLComponents(url: buildURL(path: "Items"), resolvingAgainstBaseURL: false)!
            var queryItems: [URLQueryItem] = [
                URLQueryItem(name: "IncludeItemTypes", value: "Audio"),
                URLQueryItem(name: "Recursive", value: "true"),
                URLQueryItem(name: "SortBy", value: "Album,IndexNumber"),
                URLQueryItem(name: "Fields", value: "Name,RunTimeTicks,AlbumId,Album,Artists,Genres,IndexNumber,DiscNumber,ParentId,ImageTags,UserData,DateCreated,PlayCount,Container")
            ]
            
            if let userId = userId {
                queryItems.append(URLQueryItem(name: "UserId", value: userId))
                queryItems.append(URLQueryItem(name: "EnableUserData", value: "true"))
            }
            
            if let albumId = byAlbumId {
                queryItems.append(URLQueryItem(name: "ParentId", value: albumId))
            } else if let artistId = byArtistId {
                queryItems.append(URLQueryItem(name: "ArtistIds", value: artistId))
            }
            
            components.queryItems = queryItems
            
            guard let url = components.url else {
                throw JellyfinAPIError.invalidResponse
            }
            
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            addAuthHeaders(to: &request)
            
            do {
                let result: JellyfinBaseItemQueryResult = try await httpClient.request(request)
                
                let tracks = result.items.compactMap { item -> JellyfinTrackDTO? in
                    guard item.type == "Audio" else { return nil }
                    
                    return JellyfinTrackDTO(
                        id: item.id,
                        name: item.name,
                        albumId: item.albumId,
                        album: item.album,
                        artists: item.artists,
                        genres: item.genres,
                        runTimeTicks: item.runTimeTicks,
                        indexNumber: item.indexNumber,
                        discNumber: item.discNumber,
                        dateAdded: item.dateAdded,
                        playCount: item.playCount,
                        container: item.container,
                        userData: item.userData,
                        playlistItemId: nil
                    )
                }
                
                return tracks
            } catch {
                throw error
            }
        } else {
            // Paginated fetch for all tracks
            let pageSize = 1000
            var allTracks: [JellyfinTrackDTO] = []
            var startIndex = 0
            var totalRecordCount: Int?
            
            repeat {
                var components = URLComponents(url: buildURL(path: "Items"), resolvingAgainstBaseURL: false)!
                var queryItems: [URLQueryItem] = [
                    URLQueryItem(name: "IncludeItemTypes", value: "Audio"),
                    URLQueryItem(name: "Recursive", value: "true"),
                    URLQueryItem(name: "SortBy", value: "Album,IndexNumber"),
                    URLQueryItem(name: "Limit", value: "\(pageSize)"),
                    URLQueryItem(name: "StartIndex", value: "\(startIndex)"),
                    URLQueryItem(name: "Fields", value: "Name,RunTimeTicks,AlbumId,Album,Artists,Genres,IndexNumber,DiscNumber,ParentId,ImageTags,UserData,DateCreated,PlayCount,Container")
                ]
                
                if let userId = userId {
                    queryItems.append(URLQueryItem(name: "UserId", value: userId))
                    queryItems.append(URLQueryItem(name: "EnableUserData", value: "true"))
                }
                
                components.queryItems = queryItems
                
                guard let url = components.url else {
                    throw JellyfinAPIError.invalidResponse
                }
                
                var request = URLRequest(url: url)
                request.httpMethod = "GET"
                addAuthHeaders(to: &request)
                
                do {
                    let result: JellyfinBaseItemQueryResult = try await httpClient.request(request)
                    
                    if totalRecordCount == nil {
                        totalRecordCount = result.totalRecordCount
                    }
                    
                    let pageTracks = result.items.compactMap { item -> JellyfinTrackDTO? in
                        guard item.type == "Audio" else { return nil }
                        
                        return JellyfinTrackDTO(
                            id: item.id,
                            name: item.name,
                            albumId: item.albumId,
                            album: item.album,
                            artists: item.artists,
                            genres: item.genres,
                            runTimeTicks: item.runTimeTicks,
                            indexNumber: item.indexNumber,
                            discNumber: item.discNumber,
                            dateAdded: item.dateAdded,
                            playCount: item.playCount,
                            container: item.container,
                            userData: item.userData,
                            playlistItemId: nil
                        )
                    }
                    
                    allTracks.append(contentsOf: pageTracks)
                    startIndex += pageTracks.count
                    
                    if let total = totalRecordCount, startIndex >= total {
                        break
                    }
                    
                    if pageTracks.count < pageSize {
                        break
                    }
                } catch {
                    throw error
                }
            } while true
            
            return allTracks
        }
    }
}

