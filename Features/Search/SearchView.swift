
import SwiftUI

struct SearchView: View {
    @EnvironmentObject var coordinator: AppCoordinator
    @State private var searchText = ""
    @State private var searchResults = SearchResults(tracks: [], albums: [], artists: [])
    @State private var isLoading = false
    @State private var error: String?
    @State private var selectedTrack: Track?
    @State private var showingInstantMixAlert = false
    @State private var preloadedPlaylists: [Playlist] = []
    @State private var playlistsLoaded = false
    
    // Sorting state for each section
    @State private var trackSortOption: TrackSortOption = .title
    @State private var trackAscending: Bool = true
    @State private var albumSortOption: AlbumSortOption = .title
    @State private var albumAscending: Bool = true
    @State private var artistSortOption: ArtistSortOption = .name
    @State private var artistAscending: Bool = true
    
    private var sortedTracks: [Track] {
        searchResults.tracks.sorted { track1, track2 in
            let result: Bool
            switch trackSortOption {
            case .title:
                result = track1.title.localizedCompare(track2.title) == .orderedAscending
            case .artist:
                result = track1.artistName.localizedCompare(track2.artistName) == .orderedAscending
            case .album:
                result = (track1.albumTitle ?? "").localizedCompare(track2.albumTitle ?? "") == .orderedAscending
            case .duration:
                result = track1.duration < track2.duration
            case .dateAdded:
                let date1 = track1.dateAdded ?? Date.distantPast
                let date2 = track2.dateAdded ?? Date.distantPast
                result = date1 < date2
            case .trackNumber:
                let num1 = track1.trackNumber ?? Int.max
                let num2 = track2.trackNumber ?? Int.max
                result = num1 < num2
            case .discNumber:
                let num1 = track1.discNumber ?? Int.max
                let num2 = track2.discNumber ?? Int.max
                result = num1 < num2
            case .playCount:
                result = track1.playCount < track2.playCount
            }
            return trackAscending ? result : !result
        }
    }
    
    private var sortedAlbums: [Album] {
        searchResults.albums.sorted { album1, album2 in
            let result: Bool
            switch albumSortOption {
            case .title:
                result = album1.title.localizedCompare(album2.title) == .orderedAscending
            case .artist:
                result = album1.artistName.localizedCompare(album2.artistName) == .orderedAscending
            case .year:
                let year1 = album1.year ?? Int.max
                let year2 = album2.year ?? Int.max
                result = year1 < year2
            }
            return albumAscending ? result : !result
        }
    }
    
    private var sortedArtists: [Artist] {
        searchResults.artists.sorted { artist1, artist2 in
            let result: Bool
            switch artistSortOption {
            case .name:
                result = artist1.name.localizedCompare(artist2.name) == .orderedAscending
            }
            return artistAscending ? result : !result
        }
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                SearchBar(text: $searchText)
                    .onSubmit {
                        Task {
                            await performSearch()
                        }
                    }
                    .onChange(of: searchText) { oldValue, newValue in
                        if newValue.isEmpty {
                            searchResults = SearchResults(tracks: [], albums: [], artists: [])
                        } else if newValue.count >= 2 {
                            // Debounce search - perform after user stops typing
                            Task {
                                try? await Task.sleep(nanoseconds: 300_000_000) // 300ms
                                if searchText == newValue {
                                    await performSearch()
                                }
                            }
                        }
                    }
                
                if isLoading {
                    Spacer()
                    ProgressView("Searching...")
                    Spacer()
                } else if let error = error {
                    Spacer()
                    Text("Error: \(error)")
                        .foregroundColor(.red)
                        .padding()
                    Spacer()
                } else if searchText.isEmpty {
                    Spacer()
                    Text("Enter a search term to find tracks, albums, and artists")
                        .foregroundStyle(Color("AppTextSecondary"))
                        .multilineTextAlignment(.center)
                        .padding()
                    Spacer()
                } else if searchResults.isEmpty {
                    Spacer()
                    Text("No results found")
                        .foregroundStyle(Color("AppTextSecondary"))
                        .padding()
                    Spacer()
                } else {
                    List {
                        // Artists Section
                        if !sortedArtists.isEmpty {
                            Section {
                                // Header row with sorting
                                HStack {
                                    Text("Artists")
                                        .font(.headline)
                                    Spacer()
                                    SortingMenu(selectedOption: $artistSortOption, ascending: $artistAscending)
                                }
                                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 4, trailing: 16))
                                .listRowBackground(Color.clear)
                                
                                ForEach(sortedArtists) { artist in
                                    NavigationLink(value: artist) {
                                        HStack {
                                            Text(artist.name)
                                                .font(.headline)
                                            Spacer()
                                        }
                                    }
                                }
                            }
                        }
                        
                        // Albums Section
                        if !sortedAlbums.isEmpty {
                            Section {
                                // Header row with sorting
                                HStack {
                                    Text("Albums")
                                        .font(.headline)
                                    Spacer()
                                    SortingMenu(selectedOption: $albumSortOption, ascending: $albumAscending)
                                }
                                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 4, trailing: 16))
                                .listRowBackground(Color.clear)
                                
                                ForEach(sortedAlbums) { album in
                                    NavigationLink(value: album) {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(album.title)
                                                .font(.headline)
                                            Text(album.artistName)
                                                .font(.caption)
                                                .foregroundStyle(Color("AppTextSecondary"))
                                        }
                                    }
                                }
                            }
                        }
                        
                        // Tracks Section
                        if !sortedTracks.isEmpty {
                            Section {
                                // Header row with sorting
                                HStack {
                                    Text("Tracks")
                                        .font(.headline)
                                    Spacer()
                                    SortingMenu(selectedOption: $trackSortOption, ascending: $trackAscending)
                                }
                                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 4, trailing: 16))
                                .listRowBackground(Color.clear)
                                
                                ForEach(Array(sortedTracks.enumerated()), id: \.element.id) { index, track in
                                    TrackRow(track: track, onTap: {
                                        // Build queue from filtered search results
                                        coordinator.playbackViewModel.startQueue(
                                            from: sortedTracks,
                                            at: index,
                                            context: .searchResults(query: searchText)
                                        )
                                    }, menuContent: {
                                        Button {
                                            coordinator.playbackViewModel.playNext(track)
                                        } label: {
                                            Label("Play Next", systemImage: "text.line.first.and.arrowtriangle.forward")
                                        }
                                        
                                        Button {
                                            Task {
                                                await startInstantMix(from: track)
                                            }
                                        } label: {
                                            Label("Start Instant Mix", systemImage: "radio")
                                        }
                                        
                                        Button {
                                            Task {
                                                // Ensure playlists are loaded before opening sheet
                                                await ensurePlaylistsLoaded()
                                                // Set track - this will trigger the sheet via .sheet(item:)
                                                await MainActor.run {
                                                    selectedTrack = track
                                                }
                                            }
                                        } label: {
                                            Label("Add to Playlist", systemImage: "plus.circle")
                                        }
                                        
                                        // Download/Remove download button
                                        downloadButton(for: track)
                                    })
                                }
                            }
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .background(Color("AppBackground"))
                    .contentMargins(.top, 0, for: .scrollContent)
                    .safeAreaInset(edge: .bottom) {
                        Spacer()
                            .frame(height: coordinator.playbackViewModel.currentTrack != nil ? 100 : 0) // Mini player height + padding
                    }
                }
            }
            .background(Color("AppBackground"))
            .navigationTitle("Search")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: Artist.self) { artist in
                ArtistDetailView(artist: artist)
                    .environmentObject(coordinator)
            }
            .navigationDestination(for: Album.self) { album in
                AlbumDetailView(album: album)
                    .environmentObject(coordinator)
            }
        }
        .sheet(item: $selectedTrack) { track in
            AddToPlaylistSheet(
                trackIds: [track.id],
                libraryRepository: coordinator.libraryRepository,
                preloadedPlaylists: preloadedPlaylists,
                onDismiss: {
                    selectedTrack = nil
                }
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .alert("Starting Instant Mix", isPresented: $showingInstantMixAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Instant mix is starting...")
        }
        .task {
            // Pre-load playlists so they're ready when the sheet opens
            await loadPlaylists()
            playlistsLoaded = true
        }
    }
    
    private func loadPlaylists() async {
        do {
            preloadedPlaylists = try await coordinator.libraryRepository.fetchPlaylists()
        } catch {
            // Silently fail - sheet will handle loading if needed
        }
    }
    
    private func ensurePlaylistsLoaded() async {
        if !playlistsLoaded {
            await loadPlaylists()
            playlistsLoaded = true
        }
    }
    
    private func startInstantMix(from track: Track) async {
        guard let serverId = coordinator.activeServer?.id else {
            return
        }
        
        await MainActor.run {
            showingInstantMixAlert = true
        }
        
        coordinator.playbackViewModel.startInstantMix(
            from: track.id,
            kind: .song,
            serverId: serverId
        )
        
        // Dismiss alert after a short delay
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        await MainActor.run {
            showingInstantMixAlert = false
        }
    }
    
    private func performSearch() async {
        guard !searchText.trimmingCharacters(in: .whitespaces).isEmpty else {
            searchResults = SearchResults(tracks: [], albums: [], artists: [])
            return
        }
        
        isLoading = true
        error = nil
        
        do {
            searchResults = try await coordinator.searchLibraryUseCase.executeAll(query: searchText)
            isLoading = false
        } catch {
            self.error = error.localizedDescription
            isLoading = false
        }
    }
    
    @ViewBuilder
    private func downloadButton(for track: Track) -> some View {
        let status = DownloadStatusManager.getStatus(for: track.id)
        let isDownloaded = OfflineDownloadManager.shared.isDownloaded(trackId: track.id)
        
        if status == .downloading || status == .queued {
            Button {
                OfflineDownloadManager.shared.cancelDownload(for: track.id)
            } label: {
                Label("Cancel Download", systemImage: "xmark.circle")
            }
        } else if status == .downloaded || isDownloaded {
            Button(role: .destructive) {
                Task {
                    do {
                        try OfflineDownloadManager.shared.deleteDownload(for: track.id)
                    } catch {
                        // Handle error
                    }
                }
            } label: {
                Label("Remove Download", systemImage: "trash")
            }
        } else {
            Button {
                Task {
                    guard let apiClient = coordinator.apiClient else { return }
                    await OfflineDownloadManager.shared.startDownload(
                        for: track,
                        apiClient: apiClient,
                        progressCallback: { progress in
                            NotificationCenter.default.post(
                                name: .downloadProgress,
                                object: nil,
                                userInfo: ["trackId": track.id, "progress": progress]
                            )
                        }
                    )
                }
            } label: {
                Label("Download Offline", systemImage: "arrow.down.circle")
            }
        }
    }
}

struct SearchBar: View {
    @Binding var text: String
    
    var body: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
            
            TextField("Search", text: $text)
                .submitLabel(.search)
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(10)
        .padding(.horizontal)
    }
}

