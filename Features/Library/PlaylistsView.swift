
import SwiftUI
import Combine
@preconcurrency import CoreData

struct PlaylistsView: View {
    @EnvironmentObject var coordinator: AppCoordinator
    @StateObject private var viewModel = PlaylistsViewModel()
    @State private var searchText = ""
    @State private var showingCreatePlaylist = false
    
    var body: some View {
        Group {
            if viewModel.isLoading {
                ProgressView("Loading playlists...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = viewModel.error {
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                        .foregroundColor(.orange)
                    Text("Error loading playlists")
                        .font(.headline)
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(Color("AppTextSecondary"))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    if !filteredPlaylists.isEmpty {
                        ForEach(filteredPlaylists) { playlist in
                            NavigationLink(value: playlist) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(playlist.name)
                                            .font(.headline)
                                        if let summary = playlist.summary, !summary.isEmpty {
                                            Text(summary)
                                                .font(.caption)
                                                .foregroundStyle(Color("AppTextSecondary"))
                                                .lineLimit(2)
                                        }
                                        HStack(spacing: 8) {
                                            if playlist.isReadOnly {
                                                Label("Read-only", systemImage: "lock.fill")
                                                    .font(.caption2)
                                                    .foregroundColor(.orange)
                                            }
                                            if playlist.isSmart {
                                                Text("Smart Playlist")
                                                    .font(.caption2)
                                                    .foregroundColor(.blue)
                                            }
                                        }
                                    }
                                    Spacer()
                                }
                            }
                            .contextMenu {
                                Button {
                                    coordinator.playbackViewModel.startQueue(
                                        from: [],
                                        at: 0,
                                        context: .playlist(playlistId: playlist.id)
                                    )
                                    Task {
                                        let tracks = try? await coordinator.libraryRepository.fetchPlaylistTracks(playlistId: playlist.id)
                                        if let tracks = tracks, !tracks.isEmpty {
                                            await MainActor.run {
                                                coordinator.playbackViewModel.startQueue(
                                                    from: tracks,
                                                    at: 0,
                                                    context: .playlist(playlistId: playlist.id)
                                                )
                                            }
                                        }
                                    }
                                } label: {
                                    Label("Play", systemImage: "play.fill")
                                }
                                
                                Button {
                                    // Shuffle play
                                    Task {
                                        let tracks = try? await coordinator.libraryRepository.fetchPlaylistTracks(playlistId: playlist.id)
                                        if let tracks = tracks, !tracks.isEmpty {
                                            let shuffled = tracks.shuffled()
                                            await MainActor.run {
                                                coordinator.playbackViewModel.isShuffleEnabled = true
                                                coordinator.playbackViewModel.startQueue(
                                                    from: shuffled,
                                                    at: 0,
                                                    context: .playlist(playlistId: playlist.id)
                                                )
                                            }
                                        }
                                    }
                                } label: {
                                    Label("Shuffle", systemImage: "shuffle")
                                }
                                
                                if playlist.isEditable {
                                    Divider()
                                    Button(role: .destructive) {
                                        Task {
                                            let username = coordinator.activeServer?.username
                                            await viewModel.deletePlaylist(playlist, username: username)
                                        }
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                            }
                        }
                    } else if !viewModel.isLoading {
                        VStack(spacing: 16) {
                            Image(systemName: "music.note.list")
                                .font(.largeTitle)
                                .foregroundStyle(Color("AppTextSecondary"))
                            Text("No playlists found")
                                .font(.headline)
                                .foregroundStyle(Color("AppTextSecondary"))
                            Text("Create a playlist or connect to a Jellyfin server to sync playlists")
                                .font(.caption)
                                .foregroundStyle(Color("AppTextSecondary"))
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding()
                    }
                }
                .scrollContentBackground(.hidden)
                .background(Color("AppBackground"))
                .safeAreaInset(edge: .bottom) {
                    Spacer()
                        .frame(height: coordinator.playbackViewModel.currentTrack != nil ? 100 : 0) // Mini player height + padding
                }
                .searchable(text: $searchText, prompt: "Search playlists")
            }
        }
        .navigationTitle("Playlists")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showingCreatePlaylist = true
                } label: {
                    Image(systemName: "plus")
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    Task {
                        await viewModel.refresh()
                    }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
            }
        }
        .navigationDestination(for: Playlist.self) { playlist in
            PlaylistDetailView(playlist: playlist)
                .environmentObject(coordinator)
        }
        .sheet(isPresented: $showingCreatePlaylist) {
            CreatePlaylistView(
                libraryRepository: coordinator.libraryRepository,
                onDismiss: {
                    showingCreatePlaylist = false
                    Task {
                        await viewModel.load()
                    }
                }
            )
        }
        .onAppear {
            viewModel.updateRepositories(
                libraryRepository: coordinator.libraryRepository
            )
            Task {
                await viewModel.load()
            }
        }
    }
    
    private var filteredPlaylists: [Playlist] {
        let playlists: [Playlist]
        if searchText.isEmpty {
            playlists = viewModel.playlists
        } else {
            playlists = viewModel.playlists.filter { playlist in
                playlist.name.localizedCaseInsensitiveContains(searchText) ||
                (playlist.summary?.localizedCaseInsensitiveContains(searchText) ?? false)
            }
        }
        
        // Sort: editable playlists first, then read-only playlists
        return playlists.sorted { playlist1, playlist2 in
            let editable1 = playlist1.isEditable
            let editable2 = playlist2.isEditable
            
            if editable1 != editable2 {
                // Editable playlists come first
                return editable1
            }
            
            // Within each group, sort alphabetically by name
            return playlist1.name.localizedCompare(playlist2.name) == .orderedAscending
        }
    }
}

@MainActor
final class PlaylistsViewModel: ObservableObject {
    @Published var playlists: [Playlist] = []
    @Published var isLoading = false
    @Published var error: String?
    
    private var libraryRepository: LibraryRepository?
    private var coreDataStack: CoreDataStack = .shared
    
    func updateRepositories(libraryRepository: LibraryRepository) {
        self.libraryRepository = libraryRepository
    }
    
    func load() async {
        guard let libraryRepository = libraryRepository else {
            error = "Not connected to server"
            return
        }
        
        do {
            isLoading = true
            error = nil
            playlists = try await libraryRepository.fetchPlaylists()
            isLoading = false
        } catch {
            if let httpError = error as? HTTPClientError {
                self.error = httpError.errorDescription ?? httpError.localizedDescription
            } else if let apiError = error as? JellyfinAPIError {
                switch apiError {
                case .authenticationFailed:
                    self.error = "Authentication failed. Please check your credentials."
                case .invalidResponse:
                    self.error = "Invalid response from server."
                case .missingUserId, .missingAccessToken:
                    self.error = "Missing authentication information."
                case .notImplemented:
                    self.error = "Feature not yet implemented."
                }
            } else {
                self.error = error.localizedDescription
            }
            isLoading = false
        }
    }
    
    func refresh() async {
        guard let libraryRepository = libraryRepository else {
            await load()
            return
        }
        
        isLoading = true
        error = nil
        
        do {
            try await libraryRepository.syncPlaylists()
            await load()
        } catch {
            self.error = "Failed to sync playlists: \(error.localizedDescription)"
            isLoading = false
        }
    }
    
    func deletePlaylist(_ playlist: Playlist, username: String? = nil) async {
        guard playlist.isEditable else { return }
        
        guard let libraryRepository = libraryRepository else {
            self.error = "Not connected to server"
            return
        }
        
        do {
            // Delete from Jellyfin server (which also deletes from Core Data)
            try await libraryRepository.deletePlaylist(playlistId: playlist.id)
            await load()
        } catch {
            // Check if it's a 405 error (Method Not Allowed - typically means no permission)
            if case HTTPClientError.httpError(405) = error {
                let userName = username ?? "User"
                self.error = "Failed to delete playlist. User \(userName) does not have permission to delete playlists."
            } else {
                self.error = "Failed to delete playlist: \(error.localizedDescription)"
            }
        }
    }
}

struct PlaylistDetailView: View {
    let playlist: Playlist
    @EnvironmentObject var coordinator: AppCoordinator
    @Environment(\.dismiss) private var dismiss
    @State private var tracks: [Track] = []
    @State private var trackEntryIds: [String: String] = [:] // Map track ID to entry ID
    @State private var isLoading = false
    @State private var error: String?
    @State private var isEditing = false
    @State private var showingAddToPlaylist = false
    @State private var selectedTrackIds: [String] = []
    @State private var showingDeleteConfirmation = false
    
    var body: some View {
        List {
            if isLoading {
                ProgressView("Loading tracks...")
            } else if let error = error {
                Text("Error: \(error)")
                    .foregroundColor(.red)
            } else if tracks.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "music.note.list")
                        .font(.largeTitle)
                        .foregroundStyle(Color("AppTextSecondary"))
                    Text("No tracks in playlist")
                        .font(.headline)
                        .foregroundStyle(Color("AppTextSecondary"))
                }
                .frame(maxWidth: .infinity)
                .padding()
            } else {
                ForEach(Array(tracks.enumerated()), id: \.element.id) { index, track in
                    HStack(spacing: 8) {
                        if playlist.isEditable {
                            Image(systemName: "line.3.horizontal")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                                .contentShape(Rectangle())
                        }
                        
                        TrackRow(track: track, onTap: {
                            coordinator.playbackViewModel.startQueue(
                                from: tracks,
                                at: index,
                                context: .playlist(playlistId: playlist.id)
                            )
                        })
                    }
                    .contextMenu {
                        Button {
                            coordinator.playbackViewModel.playNext(track)
                        } label: {
                            Label("Play Next", systemImage: "text.line.first.and.arrowtriangle.forward")
                        }
                        
                        Button {
                            selectedTrackIds = [track.id]
                            showingAddToPlaylist = true
                        } label: {
                            Label("Add to Playlist", systemImage: "plus.circle")
                        }
                        
                        if playlist.isEditable {
                            Divider()
                            Button(role: .destructive) {
                                Task {
                                    await removeTrack(track)
                                }
                            } label: {
                                Label("Remove from Playlist", systemImage: "minus.circle")
                            }
                        }
                    }
                }
                .onMove { source, destination in
                    if playlist.isEditable {
                        moveTrack(from: source, to: destination)
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if coordinator.playbackViewModel.currentTrack != nil {
                Spacer()
                    .frame(height: 100) // Mini player height + padding
            }
        }
        .navigationTitle(playlist.name)
        .toolbar {
            if playlist.isEditable {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button(isEditing ? "Done" : "Edit") {
                            isEditing.toggle()
                        }
                        
                        Divider()
                        
                        Button(role: .destructive) {
                            showingDeleteConfirmation = true
                        } label: {
                            Label("Delete Playlist", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
        .confirmationDialog("Delete Playlist", isPresented: $showingDeleteConfirmation, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                Task {
                    await deletePlaylist()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Are you sure you want to delete \"\(playlist.name)\"? This action cannot be undone.")
        }
        .sheet(isPresented: $showingAddToPlaylist) {
            AddToPlaylistSheet(
                trackIds: selectedTrackIds,
                libraryRepository: coordinator.libraryRepository,
                onDismiss: {
                    showingAddToPlaylist = false
                    selectedTrackIds = []
                }
            )
        }
        .task {
            await loadTracks()
        }
    }
    
    private func loadTracks() async {
        isLoading = true
        error = nil
        
        do {
            tracks = try await coordinator.libraryRepository.fetchPlaylistTracks(playlistId: playlist.id)
            
            // Also fetch entry IDs for removal operations
            if playlist.isEditable {
                trackEntryIds = try await coordinator.libraryRepository.fetchPlaylistEntryIds(playlistId: playlist.id)
            }
            
            isLoading = false
        } catch {
            self.error = error.localizedDescription
            isLoading = false
        }
    }
    
    private func removeTrack(_ track: Track) async {
        guard playlist.isEditable else { return }
        
        // Get entry ID for this track
        guard let entryId = trackEntryIds[track.id] else {
            self.error = "Could not find entry ID for track. Please refresh the playlist."
            return
        }
        
        do {
            try await coordinator.libraryRepository.removeTracksFromPlaylist(playlistId: playlist.id, entryIds: [entryId])
            await loadTracks()
        } catch {
            self.error = "Failed to remove track: \(error.localizedDescription)"
        }
    }
    
    private func deletePlaylist() async {
        guard playlist.isEditable else { return }
        
        isLoading = true
        error = nil
        
        do {
            try await coordinator.libraryRepository.deletePlaylist(playlistId: playlist.id)
            // Dismiss the view after successful deletion
            await MainActor.run {
                dismiss()
            }
        } catch {
            // Check if it's a 405 error (Method Not Allowed - typically means no permission)
            if case HTTPClientError.httpError(405) = error {
                let userName = coordinator.activeServer?.username ?? "User"
                self.error = "Failed to delete playlist. User \(userName) does not have permission to delete playlists."
            } else {
                self.error = "Failed to delete playlist: \(error.localizedDescription)"
            }
            isLoading = false
        }
    }
    
    private func moveTrack(from source: IndexSet, to destination: Int) {
        guard playlist.isEditable else { return }
        
        guard let sourceIndex = source.first else { return }
        let movedTrack = tracks[sourceIndex]
        
        // Get the playlist item ID for the moved track
        guard let playlistItemId = trackEntryIds[movedTrack.id] else {
            // If we don't have the entry ID, reload to get it
            Task {
                await loadTracks()
            }
            return
        }
        
        // Calculate the new index (accounting for the move)
        // If moving down, the destination index needs to be adjusted
        let newIndex = sourceIndex < destination ? destination - 1 : destination
        
        // Update local tracks array immediately for responsive UI
        tracks.move(fromOffsets: source, toOffset: destination)
        
        // Call API to move the item on the server
        Task {
            do {
                try await coordinator.libraryRepository.movePlaylistItem(
                    playlistId: playlist.id,
                    playlistItemId: playlistItemId,
                    newIndex: newIndex
                )
                // Reload tracks to ensure sync with server
                await loadTracks()
            } catch {
                // Revert the move on error by reloading from server
                await MainActor.run {
                    Task {
                        await loadTracks()
                    }
                    self.error = "Failed to reorder track: \(error.localizedDescription)"
                }
            }
        }
    }
}

