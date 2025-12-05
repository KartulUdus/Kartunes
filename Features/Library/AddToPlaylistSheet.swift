
import SwiftUI
@preconcurrency import CoreData

struct AddToPlaylistSheet: View {
    let trackIds: [String]
    let libraryRepository: LibraryRepository
    let preloadedPlaylists: [Playlist]
    let onDismiss: () -> Void
    
    @State private var playlists: [Playlist] = []
    @State private var isLoading = true
    @State private var newPlaylistName = ""
    @State private var error: String?
    @State private var successMessage: String?
    
    init(trackIds: [String], libraryRepository: LibraryRepository, preloadedPlaylists: [Playlist] = [], onDismiss: @escaping () -> Void) {
        self.trackIds = trackIds
        self.libraryRepository = libraryRepository
        self.preloadedPlaylists = preloadedPlaylists
        self.onDismiss = onDismiss
    }
    
    var editablePlaylists: [Playlist] {
        // Only show editable playlists (not file-based M3U playlists)
        playlists.filter { $0.isEditable }
    }
    
    var body: some View {
        NavigationView {
            Group {
                if isLoading && playlists.isEmpty {
                    VStack {
                        Spacer()
                        ProgressView("Loading playlists...")
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color("AppBackground"))
                } else {
                    List {
                        if !editablePlaylists.isEmpty {
                            Section {
                                ForEach(editablePlaylists) { playlist in
                                    Button {
                                        Task {
                                            await addToPlaylist(playlist)
                                        }
                                    } label: {
                                        HStack {
                                            VStack(alignment: .leading, spacing: 4) {
                                                Text(playlist.name)
                                                    .font(.headline)
                                                    .foregroundStyle(Color("AppTextPrimary"))
                                                if let summary = playlist.summary, !summary.isEmpty {
                                                    Text(summary)
                                                        .font(.caption)
                                                        .foregroundStyle(Color("AppTextSecondary"))
                                                        .lineLimit(1)
                                                }
                                            }
                                            Spacer()
                                        }
                                    }
                                    .disabled(isLoading)
                                }
                            } header: {
                                Text("Your Playlists")
                            }
                        }
                        
                        Section {
                            TextField("New playlist name", text: $newPlaylistName)
                            Button {
                                Task {
                                    await createAndAddToPlaylist()
                                }
                            } label: {
                                HStack {
                                    Image(systemName: "plus.circle.fill")
                                    Text("Create and Add")
                                }
                            }
                            .disabled(newPlaylistName.isEmpty || isLoading)
                        } header: {
                            Text(editablePlaylists.isEmpty ? "Create Playlist" : "Create New Playlist")
                        }
                        
                        if let error = error {
                            Section {
                                Text(error)
                                    .foregroundColor(.red)
                                    .font(.caption)
                            }
                        }
                        
                        if let successMessage = successMessage {
                            Section {
                                Text(successMessage)
                                    .foregroundColor(.green)
                                    .font(.caption)
                            }
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .background(Color("AppBackground"))
                    .id(playlists.count) // Force refresh when playlists change
                }
            }
            .navigationTitle("Add to Playlist")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        onDismiss()
                    }
                }
            }
            .onAppear {
                // Set state when view appears to ensure SwiftUI updates
                if !preloadedPlaylists.isEmpty {
                    // Use Task to ensure state update happens on next run loop
                    Task { @MainActor in
                        playlists = preloadedPlaylists
                        isLoading = false
                    }
                } else if playlists.isEmpty {
                    isLoading = true
                }
            }
            .task {
                // If we have preloaded playlists and they're not set yet, set them
                if !preloadedPlaylists.isEmpty && playlists.isEmpty {
                    await MainActor.run {
                        playlists = preloadedPlaylists
                        isLoading = false
                    }
                }
                
                // Check for auto-create only if we have playlists
                if !playlists.isEmpty {
                    let editable = playlists.filter { $0.isEditable }
                    if editable.isEmpty {
                        await autoCreatePlaylist()
                    }
                } else if preloadedPlaylists.isEmpty {
                    await loadPlaylists()
                    
                    // If no editable playlists exist, automatically create one
                    let editable = playlists.filter { $0.isEditable }
                    if editable.isEmpty {
                        await autoCreatePlaylist()
                    }
                }
            }
        }
    }
    
    private func loadPlaylists() async {
        isLoading = true
        do {
            playlists = try await libraryRepository.fetchPlaylists()
            isLoading = false
        } catch {
            self.error = "Failed to load playlists: \(error.localizedDescription)"
            isLoading = false
        }
    }
    
    private func autoCreatePlaylist() async {
        // Auto-create a playlist with a default name
        let defaultName = "My Playlist"
        isLoading = true
        error = nil
        successMessage = nil
        
        do {
            // Create playlist on Jellyfin server
            let playlist = try await libraryRepository.createPlaylist(name: defaultName, summary: nil)
            
            // Add tracks to the newly created playlist
            try await libraryRepository.addTracksToPlaylist(playlistId: playlist.id, trackIds: trackIds)
            
            successMessage = "Created \"\(defaultName)\" and added tracks"
            isLoading = false
            
            // Reload playlists
            await loadPlaylists()
            
            // Clear success message and dismiss after 1.5 seconds
            Task {
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                await MainActor.run {
                    successMessage = nil
                    onDismiss()
                }
            }
        } catch {
            self.error = "Failed to create playlist: \(error.localizedDescription)"
            isLoading = false
        }
    }
    
    private func addToPlaylist(_ playlist: Playlist) async {
        guard playlist.isEditable else { return }
        
        isLoading = true
        error = nil
        successMessage = nil
        
        do {
            // Add tracks to playlist on Jellyfin server
            try await libraryRepository.addTracksToPlaylist(playlistId: playlist.id, trackIds: trackIds)
            
            successMessage = "Added to \"\(playlist.name)\""
            isLoading = false
            
            // Clear success message after 2 seconds
            Task {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                await MainActor.run {
                    successMessage = nil
                }
            }
        } catch {
            self.error = "Failed to add tracks: \(error.localizedDescription)"
            isLoading = false
        }
    }
    
    private func createAndAddToPlaylist() async {
        guard !newPlaylistName.isEmpty else { return }
        
        isLoading = true
        error = nil
        successMessage = nil
        
        do {
            // Create playlist on Jellyfin server
            let playlist = try await libraryRepository.createPlaylist(name: newPlaylistName, summary: nil)
            
            // Add tracks to the newly created playlist
            try await libraryRepository.addTracksToPlaylist(playlistId: playlist.id, trackIds: trackIds)
            
            successMessage = "Created \"\(newPlaylistName)\" and added tracks"
            newPlaylistName = ""
            isLoading = false
            
            // Reload playlists
            await loadPlaylists()
            
            // Clear success message and dismiss after 1.5 seconds
            Task {
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                await MainActor.run {
                    successMessage = nil
                    onDismiss()
                }
            }
        } catch {
            self.error = "Failed to create playlist: \(error.localizedDescription)"
            isLoading = false
        }
    }
}

