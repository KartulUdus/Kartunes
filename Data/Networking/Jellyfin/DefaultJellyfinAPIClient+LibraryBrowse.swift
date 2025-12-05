
import Foundation

extension DefaultJellyfinAPIClient {
    func fetchMusicLibraries() async throws -> [JellyfinLibraryDTO] {
        let request = buildRequest(path: "Library/VirtualFolders", method: "GET")
        
        let folders: [JellyfinVirtualFolderInfo] = try await httpClient.request(request)
        
        return folders.map { folder in
            JellyfinLibraryDTO(id: folder.itemId ?? folder.name, name: folder.name)
        }
    }
    
    func fetchArtists() async throws -> [JellyfinArtistDTO] {
        // The /Artists endpoint returns artists directly - no need for includeItemTypes
        let pageSize = 500
        var allArtists: [JellyfinArtistDTO] = []
        var startIndex = 0
        var totalRecordCount: Int?
        
        repeat {
            var components = URLComponents(url: baseURL.appendingPathComponent("Artists"), resolvingAgainstBaseURL: false)!
            var queryItems: [URLQueryItem] = [
                URLQueryItem(name: "Recursive", value: "true"),
                URLQueryItem(name: "SortBy", value: "SortName"),
                URLQueryItem(name: "Limit", value: "\(pageSize)"),
                URLQueryItem(name: "StartIndex", value: "\(startIndex)")
            ]
            
            // userId is required for non-admin users to ensure proper access control
            if let userId = userId {
                queryItems.append(URLQueryItem(name: "userId", value: userId))
            }
            
            components.queryItems = queryItems
            
            guard let url = components.url else {
                logger.error("Failed to build URL for Artists endpoint")
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
                    logger.info("Total artists available: \(result.totalRecordCount)")
                }
                
                let pageArtists = result.items.compactMap { item -> JellyfinArtistDTO? in
                    // The /Artists endpoint returns artists, type should be MusicArtist or nil
                    guard item.type == "MusicArtist" || item.type == nil else { return nil }
                    return JellyfinArtistDTO(
                        id: item.id,
                        name: item.name,
                        imageTags: item.imageTags
                    )
                }
                
                allArtists.append(contentsOf: pageArtists)
                startIndex += pageArtists.count
                
                logger.debug("Fetched \(pageArtists.count) artists (total so far: \(allArtists.count)/\(totalRecordCount ?? 0))")
                
                // Continue if we haven't fetched all items yet
                if let total = totalRecordCount, startIndex >= total {
                    break
                }
                
                // Safety check: if we got fewer items than requested, we've reached the end
                if pageArtists.count < pageSize {
                    break
                }
                
            } catch {
                logger.error("Error fetching artists: \(error.localizedDescription)")
                if let httpError = error as? HTTPClientError {
                    logger.error("HTTP Error details: \(httpError.localizedDescription)")
                }
                throw error
            }
        } while true
        
        logger.info("Successfully fetched all \(allArtists.count) artists")
        return allArtists
    }
    
    func fetchAlbums(byArtistId: String?) async throws -> [JellyfinAlbumDTO] {
        let pageSize = 500
        var allAlbums: [JellyfinAlbumDTO] = []
        var startIndex = 0
        var totalRecordCount: Int?
        
        repeat {
            var components = URLComponents(url: baseURL.appendingPathComponent("Items"), resolvingAgainstBaseURL: false)!
            var queryItems: [URLQueryItem] = [
                URLQueryItem(name: "IncludeItemTypes", value: "MusicAlbum"),
                URLQueryItem(name: "Recursive", value: "true"),
                URLQueryItem(name: "SortBy", value: "AlbumArtist,SortName"),
                URLQueryItem(name: "Limit", value: "\(pageSize)"),
                URLQueryItem(name: "StartIndex", value: "\(startIndex)")
            ]
            
            if let artistId = byArtistId {
                queryItems.append(URLQueryItem(name: "AlbumArtistIds", value: artistId))
            }
            
            // userId is required for non-admin users to ensure proper access control
            if let userId = userId {
                queryItems.append(URLQueryItem(name: "userId", value: userId))
            }
            
            components.queryItems = queryItems
            
            guard let url = components.url else {
                logger.error("Failed to build URL for Albums endpoint")
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
                }
                
                let pageAlbums = result.items.compactMap { item -> JellyfinAlbumDTO? in
                    guard item.type == "MusicAlbum" else { return nil }
                    return JellyfinAlbumDTO(
                        id: item.id,
                        name: item.name,
                        artistName: item.albumArtist,
                        productionYear: item.productionYear,
                        imageTags: item.imageTags
                    )
                }
                
                allAlbums.append(contentsOf: pageAlbums)
                startIndex += pageAlbums.count
                
                // Continue if we haven't fetched all items yet
                if let total = totalRecordCount, startIndex >= total {
                    break
                }
                
                // Safety check: if we got fewer items than requested, we've reached the end
                if pageAlbums.count < pageSize {
                    break
                }
                
            } catch {
                logger.error("Error fetching albums: \(error.localizedDescription)")
                if let httpError = error as? HTTPClientError {
                    logger.error("HTTP Error details: \(httpError.localizedDescription)")
                }
                throw error
            }
        } while true
        
        return allAlbums
    }
}

