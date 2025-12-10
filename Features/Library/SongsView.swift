
import SwiftUI
import CoreData

struct SongsView: View {
    @EnvironmentObject var coordinator: AppCoordinator
    @Environment(\.managedObjectContext) private var viewContext
    @State private var searchText = ""
    @State private var sortOption: TrackSortOption = .title
    @State private var ascending: Bool = true
    @State private var selectedTrack: Track?
    @State private var showingInstantMixAlert = false
    @State private var preloadedPlaylists: [Playlist] = []
    @State private var playlistsLoaded = false
    
    private var activeServer: CDServer? {
        guard let serverId = coordinator.activeServer?.id else { return nil }
        let request: NSFetchRequest<CDServer> = CDServer.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", serverId as CVarArg)
        request.fetchLimit = 1
        return try? viewContext.fetch(request).first
    }
    
    private var tracks: [CDTrack] {
        guard let activeServer = activeServer else { return [] }
        
        // Fetch tracks with server predicate to avoid duplicates
        let request: NSFetchRequest<CDTrack> = CDTrack.fetchRequest()
        request.predicate = NSPredicate(format: "server == %@", activeServer)
        request.sortDescriptors = [NSSortDescriptor(keyPath: \CDTrack.title, ascending: true)]
        
        guard let fetchedTracks = try? viewContext.fetch(request) else { return [] }
        
        // Deduplicate by track ID to ensure no duplicates
        var seenIds = Set<String>()
        return fetchedTracks.compactMap { track in
            guard let trackId = track.id else { return nil }
            if seenIds.contains(trackId) {
                return nil // Skip duplicate
            }
            seenIds.insert(trackId)
            return track
        }
    }
    
    private var filteredTracks: [Track] {
        guard let serverId = coordinator.activeServer?.id else { return [] }
        let filtered: [CDTrack]
        if searchText.isEmpty {
            filtered = tracks
        } else {
            filtered = tracks.filter { track in
                (track.title?.localizedCaseInsensitiveContains(searchText) ?? false) ||
                (track.artist?.name?.localizedCaseInsensitiveContains(searchText) ?? false) ||
                (track.album?.title?.localizedCaseInsensitiveContains(searchText) ?? false)
            }
        }
        
        let sorted = filtered.sorted { track1, track2 in
            let result: Bool
            switch sortOption {
            case .title:
                result = (track1.title ?? "").localizedCompare(track2.title ?? "") == .orderedAscending
            case .artist:
                result = (track1.artist?.name ?? "").localizedCompare(track2.artist?.name ?? "") == .orderedAscending
            case .album:
                result = (track1.album?.title ?? "").localizedCompare(track2.album?.title ?? "") == .orderedAscending
            case .duration:
                result = track1.duration < track2.duration
            case .dateAdded:
                let date1 = track1.dateAdded ?? Date.distantPast
                let date2 = track2.dateAdded ?? Date.distantPast
                result = date1 < date2
            case .trackNumber:
                let num1 = track1.trackNumber > 0 ? Int(track1.trackNumber) : Int.max
                let num2 = track2.trackNumber > 0 ? Int(track2.trackNumber) : Int.max
                result = num1 < num2
            case .discNumber:
                let num1 = track1.discNumber > 0 ? Int(track1.discNumber) : Int.max
                let num2 = track2.discNumber > 0 ? Int(track2.discNumber) : Int.max
                result = num1 < num2
            case .playCount:
                result = track1.playCount < track2.playCount
            }
            return ascending ? result : !result
        }
        
        return sorted.map { cdTrack in
            CoreDataTrackHelper.toDomain(cdTrack, serverId: serverId)
        }
    }
    
    var body: some View {
        List {
            if !filteredTracks.isEmpty {
                ForEach(Array(filteredTracks.enumerated()), id: \.element.id) { index, track in
                    TrackRow(track: track, onTap: {
                        // Build queue from all visible filtered/sorted tracks
                        coordinator.playbackViewModel.startQueue(
                            from: filteredTracks,
                            at: index,
                            context: .allSongs(sortedBy: sortOption, ascending: ascending)
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
            } else {
                Text("No songs found")
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
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search songs")
        .navigationTitle("Songs")
        .navigationBarTitleDisplayMode(.inline)
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
        .task {
            // Pre-load playlists so they're ready when the sheet opens
            await loadPlaylists()
            playlistsLoaded = true
        }
        .alert("Starting Instant Mix", isPresented: $showingInstantMixAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Instant mix is starting...")
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

