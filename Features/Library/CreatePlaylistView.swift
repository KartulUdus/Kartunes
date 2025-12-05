
import SwiftUI
@preconcurrency import CoreData

struct CreatePlaylistView: View {
    let libraryRepository: LibraryRepository
    let onDismiss: () -> Void
    
    @State private var playlistName = ""
    @State private var isCreating = false
    @State private var error: String?
    
    var body: some View {
        NavigationView {
            Form {
                Section {
                    TextField("Playlist Name", text: $playlistName)
                } header: {
                    Text("Playlist Details")
                }
                
                if let error = error {
                    Section {
                        Text(error)
                            .foregroundColor(.red)
                            .font(.caption)
                    }
                }
            }
            .navigationTitle("New Playlist")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        onDismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        Task {
                            await createPlaylist()
                        }
                    }
                    .disabled(playlistName.isEmpty || isCreating)
                }
            }
        }
    }
    
    private func createPlaylist() async {
        guard !playlistName.isEmpty else { return }
        
        isCreating = true
        error = nil
        
        do {
            _ = try await libraryRepository.createPlaylist(name: playlistName, summary: nil)
            
            isCreating = false
            onDismiss()
        } catch {
            self.error = error.localizedDescription
            isCreating = false
        }
    }
}

