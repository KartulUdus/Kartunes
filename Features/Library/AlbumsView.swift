
import SwiftUI
import CoreData
import UIKit

struct AlbumsView: View {
    @EnvironmentObject var coordinator: AppCoordinator
    @Environment(\.managedObjectContext) private var viewContext
    @State private var searchText = ""
    @State private var sortOption: AlbumSortOption = .title
    @State private var ascending: Bool = true
    
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \CDAlbum.sortTitle, ascending: true)],
        animation: .default
    ) private var allAlbums: FetchedResults<CDAlbum>
    
    private var activeServer: CDServer? {
        guard let serverId = coordinator.activeServer?.id else { return nil }
        let request: NSFetchRequest<CDServer> = CDServer.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", serverId as CVarArg)
        request.fetchLimit = 1
        return try? viewContext.fetch(request).first
    }
    
    private var albums: [CDAlbum] {
        guard let activeServer = activeServer else { return [] }
        return allAlbums.filter { $0.server == activeServer }
    }
    
    private var filteredAlbums: [CDAlbum] {
        let filtered: [CDAlbum]
        if searchText.isEmpty {
            filtered = albums
        } else {
            filtered = albums.filter { album in
                (album.title?.localizedCaseInsensitiveContains(searchText) ?? false) ||
                (album.artist?.name?.localizedCaseInsensitiveContains(searchText) ?? false)
            }
        }
        
        return filtered.sorted { album1, album2 in
            let result: Bool
            switch sortOption {
            case .title:
                let title1 = album1.sortTitle ?? album1.title ?? ""
                let title2 = album2.sortTitle ?? album2.title ?? ""
                result = title1.localizedCompare(title2) == .orderedAscending
            case .artist:
                result = (album1.artist?.name ?? "").localizedCompare(album2.artist?.name ?? "") == .orderedAscending
            case .year:
                result = album1.year < album2.year
            }
            return ascending ? result : !result
        }
    }
    
    var body: some View {
        List {
            if !filteredAlbums.isEmpty {
                ForEach(filteredAlbums, id: \.objectID) { cdAlbum in
                    HStack {
                        NavigationLink(value: Album(
                            id: cdAlbum.id ?? "",
                            title: cdAlbum.title ?? "",
                            artistName: cdAlbum.artist?.name ?? "Unknown Artist",
                            thumbnailURL: cdAlbum.imageURL.flatMap { URL(string: $0) },
                            year: cdAlbum.year > 0 ? Int(cdAlbum.year) : nil
                        )) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(cdAlbum.title ?? "Unknown Album")
                                    .font(.headline)
                                Text(cdAlbum.artist?.name ?? "Unknown Artist")
                                    .font(.caption)
                                    .foregroundStyle(Color("AppTextSecondary"))
                            }
                        }
                        .buttonStyle(.plain)
                        
                        Spacer()
                        
                        // Radio button for instant mix
                        Button(action: {
                            UIImpactFeedbackGenerator.medium()
                            if let albumId = cdAlbum.id, let serverId = coordinator.activeServer?.id {
                                coordinator.playbackViewModel.startInstantMix(from: albumId, kind: .album, serverId: serverId)
                            }
                        }) {
                            Image(systemName: "radio")
                                .font(.body)
                                .foregroundStyle(Color("AppTextPrimary"))
                        }
                        .buttonStyle(.plain)
                    }
                }
            } else {
                    Text("No albums found")
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
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search albums")
        .navigationTitle("Albums")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                SortingMenu(selectedOption: $sortOption, ascending: $ascending)
            }
        }
        .navigationDestination(for: Album.self) { album in
            AlbumDetailView(album: album)
                .environmentObject(coordinator)
        }
    }
}

