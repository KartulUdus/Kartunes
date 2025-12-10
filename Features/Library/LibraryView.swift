
import SwiftUI

struct LibraryView: View {
    @EnvironmentObject var coordinator: AppCoordinator
    
    var body: some View {
        NavigationStack {
            LibraryMenuView()
                .navigationDestination(for: LibraryCategory.self) { category in
                    switch category {
                    case .songs:
                        SongsView()
                            .environmentObject(coordinator)
                    case .albums:
                        AlbumsView()
                            .environmentObject(coordinator)
                    case .artists:
                        ArtistsView()
                            .environmentObject(coordinator)
                    case .playlists:
                        PlaylistsView()
                            .environmentObject(coordinator)
                    case .genres:
                        GenresView()
                            .environmentObject(coordinator)
                    case .downloads:
                        DownloadsView()
                            .environmentObject(coordinator)
                    }
                }
        }
    }
}

