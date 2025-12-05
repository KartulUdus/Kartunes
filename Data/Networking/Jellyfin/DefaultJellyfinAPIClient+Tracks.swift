
import Foundation

extension DefaultJellyfinAPIClient {
    func fetchTracks(byAlbumId: String?) async throws -> [JellyfinTrackDTO] {
        return try await fetchTracks(byAlbumId: byAlbumId, byArtistId: nil)
    }
    
    func fetchTracks(byArtistId: String?) async throws -> [JellyfinTrackDTO] {
        return try await fetchTracks(byAlbumId: nil, byArtistId: byArtistId)
    }
    
    private func fetchTracks(byAlbumId: String?, byArtistId: String?) async throws -> [JellyfinTrackDTO] {
        // If filtering by album or artist, fetch all at once (no pagination needed)
        if byAlbumId != nil || byArtistId != nil {
            var components = URLComponents(url: baseURL.appendingPathComponent("Items"), resolvingAgainstBaseURL: false)!
            var queryItems: [URLQueryItem] = [
                URLQueryItem(name: "IncludeItemTypes", value: "Audio"),
                URLQueryItem(name: "Recursive", value: "true"),
                URLQueryItem(name: "SortBy", value: "Album,IndexNumber"),
                // Request specific fields for better performance and to ensure we get genres
                URLQueryItem(name: "Fields", value: "Name,RunTimeTicks,AlbumId,Album,Artists,Genres,IndexNumber,DiscNumber,ParentId,ImageTags,UserData,DateCreated,PlayCount,Container")
            ]
            
            // userId is required for non-admin users to ensure proper access control
            if let userId = userId {
                queryItems.append(URLQueryItem(name: "userId", value: userId))
                queryItems.append(URLQueryItem(name: "EnableUserData", value: "true"))
            }
            
            if let albumId = byAlbumId {
                queryItems.append(URLQueryItem(name: "ParentId", value: albumId))
            } else if let artistId = byArtistId {
                // Use ArtistIds to filter tracks by artist (based on FinAmp approach)
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
                    guard item.type == "Audio" else {
                        return nil
                    }
                    
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
            // Fetch all tracks with pagination (for full sync)
            let pageSize = 1000
            var allTracks: [JellyfinTrackDTO] = []
            var startIndex = 0
            var totalRecordCount: Int?
            
            repeat {
                var components = URLComponents(url: baseURL.appendingPathComponent("Items"), resolvingAgainstBaseURL: false)!
                var queryItems: [URLQueryItem] = [
                    URLQueryItem(name: "IncludeItemTypes", value: "Audio"),
                    URLQueryItem(name: "Recursive", value: "true"),
                    URLQueryItem(name: "SortBy", value: "Album,IndexNumber"),
                    URLQueryItem(name: "Limit", value: "\(pageSize)"),
                    URLQueryItem(name: "StartIndex", value: "\(startIndex)"),
                    // Request specific fields for better performance and to ensure we get genres
                    URLQueryItem(name: "Fields", value: "Name,RunTimeTicks,AlbumId,Album,Artists,Genres,IndexNumber,DiscNumber,ParentId,ImageTags,UserData,DateCreated,PlayCount,Container")
                ]
                
                // userId is required for non-admin users to ensure proper access control
                if let userId = userId {
                    queryItems.append(URLQueryItem(name: "userId", value: userId))
                    queryItems.append(URLQueryItem(name: "EnableUserData", value: "true"))
                }
                
                components.queryItems = queryItems
                
                guard let url = components.url else {
                    logger.error("Failed to build URL for Tracks endpoint")
                    throw JellyfinAPIError.invalidResponse
                }
                
                var request = URLRequest(url: url)
                request.httpMethod = "GET"
                addAuthHeaders(to: &request)
                
                do {
                    let result: JellyfinBaseItemQueryResult = try await httpClient.request(request)
                    
                    // Store totalRecordCount from first request
                    if totalRecordCount == nil {
                        totalRecordCount = result.totalRecordCount
                        logger.info("Total tracks available: \(result.totalRecordCount)")
                    }
                    
                    let pageTracks = result.items.compactMap { item -> JellyfinTrackDTO? in
                        guard item.type == "Audio" else {
                            return nil
                        }
                        
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
                    
                    logger.debug("Fetched \(pageTracks.count) tracks (total so far: \(allTracks.count)/\(totalRecordCount ?? 0))")
                    
                    // Continue if we haven't fetched all items yet
                    if let total = totalRecordCount, startIndex >= total {
                        break
                    }
                    
                    // Safety check: if we got fewer items than requested, we've reached the end
                    if pageTracks.count < pageSize {
                        break
                    }
                    
                } catch {
                    logger.error("Error fetching tracks: \(error.localizedDescription)")
                    if let httpError = error as? HTTPClientError {
                        logger.error("HTTP Error details: \(httpError.localizedDescription)")
                    }
                    throw error
                }
            } while true
            
            logger.info("Successfully fetched all \(allTracks.count) tracks")
            logger.debug("Fetched \(allTracks.count) tracks from Jellyfin API")
            if !allTracks.isEmpty {
                logger.debug("First track sample - ID: \(allTracks[0].id), Title: \(allTracks[0].name)")
            }
            return allTracks
        }
    }
}

