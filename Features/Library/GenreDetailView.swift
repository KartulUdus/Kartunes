
import SwiftUI
import CoreData

struct GenreDetailView: View {
    let genre: GenreItem
    @EnvironmentObject var coordinator: AppCoordinator
    @Environment(\.managedObjectContext) private var viewContext
    @State private var tracks: [Track] = []
    @State private var isLoading = false
    @State private var error: String?
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
    
    private var filteredTracks: [Track] {
        guard coordinator.activeServer?.id != nil else { return [] }
        
        let sorted = tracks.sorted { track1, track2 in
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
        
        return sorted
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
                ForEach(Array(filteredTracks.enumerated()), id: \.element.id) { index, track in
                    TrackRow(track: track, onTap: {
                        coordinator.playbackViewModel.startQueue(
                            from: filteredTracks,
                            at: index,
                            context: .genre(genreName: genre.name, isUmbrella: genre.isUmbrella)
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
                    })
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
        .navigationTitle(genre.name)
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
    
    private func loadTracks() async {
        guard let activeServer = activeServer, let serverId = coordinator.activeServer?.id else {
            await MainActor.run {
                isLoading = false
                error = "No active server"
            }
            return
        }
        
        await MainActor.run {
            isLoading = true
            error = nil
        }
        
        // Find all genres matching the selected genre
        let request: NSFetchRequest<CDGenre> = CDGenre.fetchRequest()
        if genre.isUmbrella {
            request.predicate = NSPredicate(format: "server == %@ AND umbrellaName == %@", activeServer, genre.name)
        } else {
            request.predicate = NSPredicate(format: "server == %@ AND normalizedName == %@", activeServer, genre.name)
        }
        
        guard let matchingGenres = try? viewContext.fetch(request) else {
            await MainActor.run {
                isLoading = false
                error = "Failed to fetch genres"
            }
            return
        }
        
        // Collect all unique tracks from matching genres
        var trackSet = Set<CDTrack>()
        for cdGenre in matchingGenres {
            if let genreTracks = cdGenre.tracks as? Set<CDTrack> {
                trackSet.formUnion(genreTracks)
            }
        }
        
        // Filter to only tracks from the active server
        let serverTracks = trackSet.filter { $0.server == activeServer }
        
        // Convert to domain tracks
        let domainTracks = serverTracks.map { cdTrack in
            CoreDataTrackHelper.toDomain(cdTrack, serverId: serverId)
        }
        
        await MainActor.run {
            tracks = domainTracks
            isLoading = false
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
}

