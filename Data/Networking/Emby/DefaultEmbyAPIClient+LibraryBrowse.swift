
import Foundation

extension DefaultEmbyAPIClient {
    func fetchArtistsImpl() async throws -> [JellyfinArtistDTO] {
        let pageSize = 500
        var allArtists: [JellyfinArtistDTO] = []
        var startIndex = 0
        var totalRecordCount: Int?
        
        repeat {
            var components = URLComponents(url: buildURL(path: "Artists"), resolvingAgainstBaseURL: false)!
            var queryItems: [URLQueryItem] = [
                URLQueryItem(name: "Recursive", value: "true"),
                URLQueryItem(name: "SortBy", value: "SortName"),
                URLQueryItem(name: "Limit", value: "\(pageSize)"),
                URLQueryItem(name: "StartIndex", value: "\(startIndex)"),
                URLQueryItem(name: "Fields", value: "ImageTags") // Request ImageTags for album art
            ]
            
            if let userId = userId {
                queryItems.append(URLQueryItem(name: "UserId", value: userId))
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
                
                let pageArtists = result.items.compactMap { item -> JellyfinArtistDTO? in
                    guard item.type == "MusicArtist" || item.type == nil else { return nil }
                    return JellyfinArtistDTO(
                        id: item.id,
                        name: item.name,
                        imageTags: item.imageTags
                    )
                }
                
                allArtists.append(contentsOf: pageArtists)
                startIndex += pageArtists.count
                
                if let total = totalRecordCount, startIndex >= total {
                    break
                }
                
                if pageArtists.count < pageSize {
                    break
                }
            } catch {
                throw error
            }
        } while true
        
        return allArtists
    }
    
    func fetchAlbumsImpl(byArtistId: String?) async throws -> [JellyfinAlbumDTO] {
        let pageSize = 500
        var allAlbums: [JellyfinAlbumDTO] = []
        var startIndex = 0
        var totalRecordCount: Int?
        
        repeat {
            var components = URLComponents(url: buildURL(path: "Items"), resolvingAgainstBaseURL: false)!
            var queryItems: [URLQueryItem] = [
                URLQueryItem(name: "IncludeItemTypes", value: "MusicAlbum"),
                URLQueryItem(name: "Recursive", value: "true"),
                URLQueryItem(name: "SortBy", value: "AlbumArtist,SortName"),
                URLQueryItem(name: "Limit", value: "\(pageSize)"),
                URLQueryItem(name: "StartIndex", value: "\(startIndex)"),
                URLQueryItem(name: "Fields", value: "ImageTags,ProductionYear") // Request ImageTags for album art
            ]
            
            if let artistId = byArtistId {
                queryItems.append(URLQueryItem(name: "AlbumArtistIds", value: artistId))
            }
            
            if let userId = userId {
                queryItems.append(URLQueryItem(name: "UserId", value: userId))
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
                
                var pageAlbums: [JellyfinAlbumDTO] = []
                for item in result.items {
                    guard item.type == "MusicAlbum" else { continue }
                    
                    var imageTags = item.imageTags
                    
                    // Debug: Log ImageTags for Emby
                    if let tags = imageTags, !tags.isEmpty {
                        logger.debug("Album '\(item.name)' (ID: \(item.id)) ImageTags: \(tags)")
                    } else {
                        logger.warning("Album '\(item.name)' (ID: \(item.id)) has no ImageTags in list response")
                        // Try to fetch album details to get ImageTags
                        // Use the Items endpoint with the album ID and Fields=ImageTags
                        if let fetchedTags = try? await fetchAlbumImageTags(albumId: item.id) {
                            imageTags = fetchedTags
                            if let tags = imageTags, !tags.isEmpty {
                                logger.debug("Fetched ImageTags for album '\(item.name)' (ID: \(item.id)): \(tags)")
                            }
                        }
                    }
                    
                    pageAlbums.append(JellyfinAlbumDTO(
                        id: item.id,
                        name: item.name,
                        artistName: item.albumArtist,
                        productionYear: item.productionYear,
                        imageTags: imageTags
                    ))
                }
                
                allAlbums.append(contentsOf: pageAlbums)
                startIndex += pageAlbums.count
                
                if let total = totalRecordCount, startIndex >= total {
                    break
                }
                
                if pageAlbums.count < pageSize {
                    break
                }
            } catch {
                throw error
            }
        } while true
        
        return allAlbums
    }
    
    /// Fetches ImageTags for a specific album by querying the Items endpoint with the album ID
    func fetchAlbumImageTags(albumId: String) async throws -> [String: String]? {
        var components = URLComponents(url: buildURL(path: "Items"), resolvingAgainstBaseURL: false)!
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "Ids", value: albumId),
            URLQueryItem(name: "Fields", value: "ImageTags")
        ]
        
        if let userId = userId {
            queryItems.append(URLQueryItem(name: "UserId", value: userId))
        }
        
        components.queryItems = queryItems
        
        guard let url = components.url else {
            return nil
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        addAuthHeaders(to: &request)
        
        do {
            let result: JellyfinBaseItemQueryResult = try await httpClient.request(request)
            logger.debug("fetchAlbumImageTags response for album \(albumId) - items count: \(result.items.count)")
            
            if let album = result.items.first(where: { $0.id == albumId && $0.type == "MusicAlbum" }) {
                logger.debug("Found album \(albumId), ImageTags: \(album.imageTags ?? [:])")
                if let imageTags = album.imageTags, !imageTags.isEmpty {
                    return imageTags
                } else {
                    // Try to get ImageTags from the raw response - sometimes they're in a different format
                    logger.warning("Album \(albumId) has empty ImageTags in response")
                }
            } else {
                logger.warning("Album \(albumId) not found in response items")
                // Log all item types we got back
                for item in result.items {
                    logger.debug("Response item - ID: \(item.id), Type: \(item.type ?? "nil"), ImageTags: \(item.imageTags ?? [:])")
                }
            }
        } catch {
            logger.warning("Failed to fetch ImageTags for album \(albumId): \(error.localizedDescription)")
        }
        
        return nil
    }
}

