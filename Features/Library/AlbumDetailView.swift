
import SwiftUI
import UIKit

struct AlbumDetailView: View {
    let album: Album
    @EnvironmentObject var coordinator: AppCoordinator
    @State private var tracks: [Track] = []
    @State private var isLoading = false
    @State private var error: String?
    @State private var sortOption: TrackSortOption = .trackNumber
    @State private var ascending: Bool = true
    @State private var selectedTrack: Track?
    @State private var showingInstantMixAlert = false
    @State private var preloadedPlaylists: [Playlist] = []
    @State private var playlistsLoaded = false
    
    init(album: Album) {
        self.album = album
    }
    
    private var sortedTracks: [Track] {
        tracks.sorted { track1, track2 in
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
    
    var body: some View {
        List {
            if isLoading {
                ProgressView("Loading tracks...")
            } else if let error = error {
                Text("Error: \(error)")
                    .foregroundColor(.red)
            } else {
                ForEach(Array(sortedTracks.enumerated()), id: \.element.id) { index, track in
                    TrackRow(track: track, onTap: {
                        // For albums, use proper album order (disc number, then track number, then title)
                        // The sortedTracks should already be sorted correctly, but ensure album order
                        let albumOrderedTracks = tracks.sorted { track1, track2 in
                            // Sort by disc number first
                            let disc1 = track1.discNumber ?? 0
                            let disc2 = track2.discNumber ?? 0
                            if disc1 != disc2 {
                                return disc1 < disc2
                            }
                            // Then by track number
                            let trackNum1 = track1.trackNumber ?? Int.max
                            let trackNum2 = track2.trackNumber ?? Int.max
                            if trackNum1 != trackNum2 {
                                return trackNum1 < trackNum2
                            }
                            // Finally by title
                            return track1.title.localizedCompare(track2.title) == .orderedAscending
                        }
                        
                        // Find the index in the album-ordered list
                        if let albumIndex = albumOrderedTracks.firstIndex(where: { $0.id == track.id }) {
                            coordinator.playbackViewModel.startQueue(
                                from: albumOrderedTracks,
                                at: albumIndex,
                                context: .album(albumId: album.id)
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
                    })
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            Spacer()
                .frame(height: coordinator.playbackViewModel.currentTrack != nil ? 100 : 0) // Mini player height + padding
        }
        .navigationTitle(album.title)
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
            // Validate album ID
            guard !album.id.isEmpty else {
                throw NSError(domain: "Kartunes", code: -1, userInfo: [NSLocalizedDescriptionKey: "Album ID is missing"])
            }
            
            tracks = try await coordinator.libraryRepository.fetchTracks(albumId: album.id)
            
            if tracks.isEmpty {
                error = "No tracks found for this album."
            }
            
            isLoading = false
        } catch {
            if let httpError = error as? HTTPClientError {
                self.error = httpError.errorDescription ?? httpError.localizedDescription
            } else if let repoError = error as? LibraryRepositoryError {
                self.error = repoError.localizedDescription
            } else {
                self.error = error.localizedDescription
            }
            isLoading = false
        }
    }
}

struct TrackRow<MenuContent: View>: View {
    let track: Track
    let onTap: () -> Void
    let menuContent: (() -> MenuContent)?
    
    init(track: Track, onTap: @escaping () -> Void, @ViewBuilder menuContent: @escaping () -> MenuContent) {
        self.track = track
        self.onTap = onTap
        self.menuContent = menuContent
    }
    
    init(track: Track, onTap: @escaping () -> Void) where MenuContent == EmptyView {
        self.track = track
        self.onTap = onTap
        self.menuContent = nil
    }
    
    var body: some View {
        Button(action: {
            UIImpactFeedbackGenerator.light()
            onTap()
        }) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(track.title)
                        .font(.headline)
                        .foregroundStyle(Color("AppTextPrimary"))
                    Text(track.artistName)
                        .font(.caption)
                        .foregroundStyle(Color("AppTextSecondary"))
                }
                
                Spacer()
                
                HStack(spacing: 8) {
                    Text(formatDuration(track.duration))
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    if let menuContent = menuContent {
                        Menu {
                            menuContent()
                        } label: {
                            Image(systemName: "ellipsis")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle()) // Makes entire area tappable
        }
        .buttonStyle(.plain)
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        // Handle invalid time values
        guard duration.isFinite && !duration.isNaN && duration >= 0 else {
            return "0:00"
        }
        
        let totalSeconds = Int(duration.rounded())
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

