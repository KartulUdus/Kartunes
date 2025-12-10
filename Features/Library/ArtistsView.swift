
import SwiftUI
import CoreData
import UIKit

struct ArtistsView: View {
    @EnvironmentObject var coordinator: AppCoordinator
    @Environment(\.managedObjectContext) private var viewContext
    @State private var searchText = ""
    @State private var sortOption: ArtistSortOption = .name
    @State private var ascending: Bool = true
    
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \CDArtist.sortName, ascending: true)],
        animation: .default
    ) private var allArtists: FetchedResults<CDArtist>
    
    private var activeServer: CDServer? {
        guard let serverId = coordinator.activeServer?.id else { return nil }
        let request: NSFetchRequest<CDServer> = CDServer.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", serverId as CVarArg)
        request.fetchLimit = 1
        return try? viewContext.fetch(request).first
    }
    
    private var artists: [CDArtist] {
        guard let activeServer = activeServer else { return [] }
        return allArtists.filter { $0.server == activeServer }
    }
    
    private var filteredArtists: [CDArtist] {
        let filtered: [CDArtist]
        if searchText.isEmpty {
            filtered = artists
        } else {
            filtered = artists.filter { artist in
                (artist.name?.localizedCaseInsensitiveContains(searchText) ?? false)
            }
        }
        
        return filtered.sorted { artist1, artist2 in
            let result: Bool
            switch sortOption {
            case .name:
                let name1 = artist1.sortName ?? artist1.name ?? ""
                let name2 = artist2.sortName ?? artist2.name ?? ""
                result = name1.localizedCompare(name2) == .orderedAscending
            }
            return ascending ? result : !result
        }
    }
    
    var body: some View {
        List {
            if !filteredArtists.isEmpty {
                ForEach(filteredArtists, id: \.objectID) { cdArtist in
                    HStack {
                        NavigationLink(value: Artist(
                            id: cdArtist.id ?? "",
                            name: cdArtist.name ?? "",
                            thumbnailURL: cdArtist.imageURL.flatMap { URL(string: $0) }
                        )) {
                            HStack {
                                Text(cdArtist.name ?? "Unknown Artist")
                                    .font(.headline)
                                Spacer()
                            }
                        }
                        .buttonStyle(.plain)
                        
                        Spacer()
                        
                        // Radio button for instant mix (hidden for Emby - no Artist InstantMix support)
                        if coordinator.activeServer?.serverType != .emby {
                            Button(action: {
                                UIImpactFeedbackGenerator.medium()
                                if let artistId = cdArtist.id, let serverId = coordinator.activeServer?.id {
                                    coordinator.playbackViewModel.startInstantMix(from: artistId, kind: .artist, serverId: serverId)
                                }
                            }) {
                                Image(systemName: "radio")
                                    .font(.body)
                                    .foregroundStyle(Color("AppTextPrimary"))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            } else {
                Text("No artists found")
                    .foregroundStyle(Color("AppTextSecondary"))
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding()
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
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search artists")
        .navigationTitle("Artists")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                SortingMenu(selectedOption: $sortOption, ascending: $ascending)
            }
        }
        .navigationDestination(for: Artist.self) { artist in
            ArtistDetailView(artist: artist)
                .environmentObject(coordinator)
        }
    }
}

// Artist detail view showing tracks grouped by album
struct ArtistDetailView: View {
    let artist: Artist
    @EnvironmentObject var coordinator: AppCoordinator
    @State private var tracks: [Track] = []
    @State private var isLoading = false
    @State private var error: String?
    @State private var sortOption: TrackSortOption = .album
    @State private var ascending: Bool = true
    @State private var selectedTrack: Track?
    @State private var showingInstantMixAlert = false
    @State private var preloadedPlaylists: [Playlist] = []
    @State private var playlistsLoaded = false
    
    // Group tracks by album and sort within each album
    private var tracksByAlbum: [String: [Track]] {
        let grouped = Dictionary(grouping: tracks) { track in
            track.albumTitle ?? "Unknown Album"
        }
        // Sort tracks within each album based on sort option
        return grouped.mapValues { albumTracks in
            albumTracks.sorted { track1, track2 in
                let result: Bool
                switch sortOption {
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
                return ascending ? result : !result
            }
        }
    }
    
    // Sorted album titles
    private var sortedAlbumTitles: [String] {
        Array(tracksByAlbum.keys).sorted()
    }
    
    var body: some View {
        List {
            if isLoading {
                ProgressView("Loading tracks...")
            } else if let error = error {
                Text("Error: \(error)")
                    .foregroundColor(.red)
            } else if tracks.isEmpty {
                Text("No tracks found")
                    .foregroundStyle(Color("AppTextSecondary"))
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding()
            } else {
                // Build a flat list of all tracks in sorted order for queue
                let allTracksFlat: [Track] = sortedAlbumTitles.flatMap { albumTitle in
                    tracksByAlbum[albumTitle] ?? []
                }
                
                ForEach(sortedAlbumTitles, id: \.self) { albumTitle in
                    Section(header: Text(albumTitle)
                        .font(.headline)
                        .textCase(nil)) {
                        ForEach(Array((tracksByAlbum[albumTitle] ?? []).enumerated()), id: \.element.id) { albumIndex, track in
                            TrackRow(track: track, onTap: {
                                // Find the index in the flat list
                                if let globalIndex = allTracksFlat.firstIndex(where: { $0.id == track.id }) {
                                    coordinator.playbackViewModel.startQueue(
                                        from: allTracksFlat,
                                        at: globalIndex,
                                        context: .artist(artistId: artist.id)
                                    )
                                }
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
        }
        .safeAreaInset(edge: .bottom) {
            Spacer()
                .frame(height: coordinator.playbackViewModel.currentTrack != nil ? 100 : 0) // Mini player height + padding
        }
        .navigationTitle(artist.name)
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                SortingMenu(selectedOption: $sortOption, ascending: $ascending)
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
            await loadTracks()
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
    
    private func loadTracks() async {
        isLoading = true
        error = nil
        
        do {
            tracks = try await coordinator.libraryRepository.fetchTracks(artistId: artist.id)
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

