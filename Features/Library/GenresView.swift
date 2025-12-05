
import SwiftUI
import CoreData

struct GenreItem: Identifiable, Hashable {
    let id: String
    let name: String
    let trackCount: Int
    let isUmbrella: Bool
}

struct GenresView: View {
    @EnvironmentObject var coordinator: AppCoordinator
    @Environment(\.managedObjectContext) private var viewContext
    @State private var searchText = ""
    
    private var activeServer: CDServer? {
        guard let serverId = coordinator.activeServer?.id else { return nil }
        let request: NSFetchRequest<CDServer> = CDServer.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", serverId as CVarArg)
        request.fetchLimit = 1
        return try? viewContext.fetch(request).first
    }
    
    private var umbrellaGenres: [GenreItem] {
        guard let activeServer = activeServer else { return [] }
        
        // Fetch all genres with umbrella names for this server
        let request: NSFetchRequest<CDGenre> = CDGenre.fetchRequest()
        request.predicate = NSPredicate(format: "server == %@ AND umbrellaName != nil", activeServer)
        
        guard let genres = try? viewContext.fetch(request) else { return [] }
        
        // Group by umbrella name and collect unique tracks
        var genreTracks: [String: Set<CDTrack>] = [:]
        for genre in genres {
            guard let umbrellaName = genre.umbrellaName, !umbrellaName.isEmpty else { continue }
            if let tracks = genre.tracks as? Set<CDTrack> {
                // Filter to only tracks from the active server
                let serverTracks = tracks.filter { $0.server == activeServer }
                if genreTracks[umbrellaName] == nil {
                    genreTracks[umbrellaName] = Set<CDTrack>()
                }
                genreTracks[umbrellaName]?.formUnion(serverTracks)
            }
        }
        
        // Convert to GenreItem array with unique track counts and sort by count descending
        return genreTracks.map { name, tracks in
            GenreItem(id: "umbrella_\(name)", name: name, trackCount: tracks.count, isUmbrella: true)
        }.sorted { $0.trackCount > $1.trackCount }
    }
    
    private var normalizedGenres: [GenreItem] {
        guard let activeServer = activeServer else { return [] }
        
        // Fetch all genres for this server
        let request: NSFetchRequest<CDGenre> = CDGenre.fetchRequest()
        request.predicate = NSPredicate(format: "server == %@", activeServer)
        
        guard let genres = try? viewContext.fetch(request) else { return [] }
        
        // Group by normalized name and collect unique tracks
        var genreTracks: [String: Set<CDTrack>] = [:]
        for genre in genres {
            guard let normalizedName = genre.normalizedName, !normalizedName.isEmpty else { continue }
            if let tracks = genre.tracks as? Set<CDTrack> {
                // Filter to only tracks from the active server
                let serverTracks = tracks.filter { $0.server == activeServer }
                if genreTracks[normalizedName] == nil {
                    genreTracks[normalizedName] = Set<CDTrack>()
                }
                genreTracks[normalizedName]?.formUnion(serverTracks)
            }
        }
        
        // Convert to GenreItem array with unique track counts and sort by count descending
        return genreTracks.map { name, tracks in
            GenreItem(id: "normalized_\(name)", name: name, trackCount: tracks.count, isUmbrella: false)
        }.sorted { $0.trackCount > $1.trackCount }
    }
    
    private var filteredUmbrellaGenres: [GenreItem] {
        if searchText.isEmpty {
            return umbrellaGenres
        } else {
            return umbrellaGenres.filter { genre in
                genre.name.localizedCaseInsensitiveContains(searchText)
            }
        }
    }
    
    private var filteredNormalizedGenres: [GenreItem] {
        if searchText.isEmpty {
            return normalizedGenres
        } else {
            return normalizedGenres.filter { genre in
                genre.name.localizedCaseInsensitiveContains(searchText)
            }
        }
    }
    
    var body: some View {
        List {
            if !filteredUmbrellaGenres.isEmpty {
                Section(header: Text("Umbrella Genres")
                    .font(.headline)
                    .textCase(nil)) {
                    ForEach(filteredUmbrellaGenres) { genre in
                        NavigationLink(value: genre) {
                            HStack {
                                Text(genre.name)
                                    .font(.headline)
                                Spacer()
                                Text("\(genre.trackCount)")
                                    .font(.caption)
                                    .foregroundStyle(Color("AppTextSecondary"))
                            }
                        }
                    }
                }
            }
            
            if !filteredNormalizedGenres.isEmpty {
                Section(header: Text("Normalized Genres")
                    .font(.headline)
                    .textCase(nil)) {
                    ForEach(filteredNormalizedGenres) { genre in
                        NavigationLink(value: genre) {
                            HStack {
                                Text(genre.name)
                                    .font(.headline)
                                Spacer()
                                Text("\(genre.trackCount)")
                                    .font(.caption)
                                    .foregroundStyle(Color("AppTextSecondary"))
                            }
                        }
                    }
                }
            }
            
            if filteredUmbrellaGenres.isEmpty && filteredNormalizedGenres.isEmpty {
                Text("No genres found")
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
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search genres")
        .navigationTitle("Genres")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: GenreItem.self) { genre in
            GenreDetailView(genre: genre)
                .environmentObject(coordinator)
        }
    }
}

