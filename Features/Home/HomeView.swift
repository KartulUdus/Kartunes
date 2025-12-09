
import SwiftUI
import CoreData
import UIKit

struct HomeView: View {
    private static let logger = Log.make(.home)
    
    @EnvironmentObject var coordinator: AppCoordinator
    @Environment(\.managedObjectContext) private var viewContext
    @State private var isLoading = false
    @State private var genreCounts: [String: Int] = [:]
    @State private var hasLoadedGenreCounts = false
    @State private var likedCount: Int = 0
    
    // Get unique umbrella genres from the map, ordered by track count
    private var umbrellaGenres: [String] {
        let allGenres = Set(UmbrellaGenres.map.values)
        
        // If we have counts, filter to only genres with tracks and sort by count (descending)
        if !genreCounts.isEmpty {
            return allGenres
                .filter { genreCounts[$0] ?? 0 > 0 } // Only show genres with tracks
                .sorted { genre1, genre2 in
                    let count1 = genreCounts[genre1] ?? 0
                    let count2 = genreCounts[genre2] ?? 0
                    if count1 != count2 {
                        return count1 > count2 // Descending order
                    }
                    return genre1 < genre2 // Alphabetical tiebreaker
                }
        } else {
            // Before counts are loaded, return empty array (will show loading state)
            return []
        }
    }
    
    // Check if we have any genres with tracks
    private var hasGenres: Bool {
        if genreCounts.isEmpty {
            // Still loading, don't show message yet
            return true
        }
        // Check if any genre has tracks
        return genreCounts.values.contains { $0 > 0 }
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Hero Section with Primary Actions
                    HeroSection(
                        likedCount: likedCount,
                        isLoading: isLoading,
                        onShuffleLiked: { await playShuffleLiked() },
                        onRecentlyPlayed: { await playRecentlyPlayed() },
                        onRecentlyAdded: { await playRecentlyAdded() },
                        onShuffleAll: { await playShuffleAll() },
                        onRefreshLiked: { await refreshLikedTracks() }
                    )
                    
                    // Library Scan Indicator
                    if coordinator.isSyncing {
                        LibraryScanIndicator(
                            progress: coordinator.syncProgress,
                            stage: coordinator.syncStage
                        )
                    }
                    
                    // Genres Section
                    if hasLoadedGenreCounts {
                        // Genre counts have been loaded (even if empty)
                        if !umbrellaGenres.isEmpty {
                            // Show genres if we have any
                            GenresSection(
                                genres: umbrellaGenres,
                                genreCounts: genreCounts,
                                isLoading: isLoading,
                                onGenreTap: { genre in
                                    await playGenre(genre)
                                }
                            )
                        } else {
                            // No genres found after loading
                            NoGenresMessage()
                        }
                    }
                    // If hasLoadedGenreCounts is false, we're still loading, so don't show anything yet
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
            }
            .safeAreaInset(edge: .bottom) {
                Spacer()
                    .frame(height: coordinator.playbackViewModel.currentTrack != nil ? 100 : 0) // Mini player height + padding
            }
            .navigationTitle("Home")
            .task {
                await loadGenreCounts()
                await loadLikedCount()
            }
        }
    }
    
    // MARK: - Genre Count Loading
    
    private func loadGenreCounts() async {
        guard let serverId = coordinator.activeServer?.id else { return }
        
        let context = viewContext
        let counts: [String: Int] = await context.perform {
            // Find server
            let serverRequest: NSFetchRequest<CDServer> = CDServer.fetchRequest()
            serverRequest.predicate = NSPredicate(format: "id == %@", serverId as CVarArg)
            serverRequest.fetchLimit = 1
            
            guard let server = try? context.fetch(serverRequest).first else {
                return [:]
            }
            
            // Fetch all tracks for this server
            let trackRequest: NSFetchRequest<CDTrack> = CDTrack.fetchRequest()
            trackRequest.predicate = NSPredicate(format: "server == %@", server)
            
            guard let allTracks = try? context.fetch(trackRequest) else {
                return [:]
            }
            
            // Count tracks per umbrella genre
            var genreCounts: [String: Int] = [:]
            let allUmbrellaGenres = Set(UmbrellaGenres.map.values)
            
            for genre in allUmbrellaGenres {
                let count = allTracks.filter { cdTrack in
                    guard let umbrellaGenres = cdTrack.umbrellaGenres as? [String] else {
                        return false
                    }
                    return umbrellaGenres.contains(genre)
                }.count
                
                if count > 0 {
                    genreCounts[genre] = count
                }
            }
            
            return genreCounts
        }
        
        await MainActor.run {
            self.genreCounts = counts
            self.hasLoadedGenreCounts = true
        }
    }
    
    private func loadLikedCount() async {
        guard let serverId = coordinator.activeServer?.id else { return }
        
        let context = viewContext
        let count: Int = await context.perform {
            // Find server
            let serverRequest: NSFetchRequest<CDServer> = CDServer.fetchRequest()
            serverRequest.predicate = NSPredicate(format: "id == %@", serverId as CVarArg)
            serverRequest.fetchLimit = 1
            
            guard let server = try? context.fetch(serverRequest).first else {
                return 0
            }
            
            // Count liked tracks
            let trackRequest: NSFetchRequest<CDTrack> = CDTrack.fetchRequest()
            trackRequest.predicate = NSPredicate(format: "server == %@ AND isLiked == YES", server)
            
            guard let likedTracks = try? context.fetch(trackRequest) else {
                return 0
            }
            
            return likedTracks.count
        }
        
        await MainActor.run {
            self.likedCount = count
        }
    }
    
    // MARK: - Playlist Actions
    
    private func playShuffleLiked() async {
        UIImpactFeedbackGenerator.medium()
        
        await MainActor.run {
            isLoading = true
        }
        
        defer {
            Task { @MainActor in
                isLoading = false
            }
        }
        
        guard let serverId = coordinator.activeServer?.id else {
            Self.logger.warning("playShuffleLiked: No active server")
            return
        }
        
        let context = viewContext
        let tracks: [Track] = await context.perform {
            // Find server
            let serverRequest: NSFetchRequest<CDServer> = CDServer.fetchRequest()
            serverRequest.predicate = NSPredicate(format: "id == %@", serverId as CVarArg)
            serverRequest.fetchLimit = 1
            
            guard let server = try? context.fetch(serverRequest).first else {
                return []
            }
            
            // Fetch liked tracks
            let trackRequest: NSFetchRequest<CDTrack> = CDTrack.fetchRequest()
            trackRequest.predicate = NSPredicate(format: "server == %@ AND isLiked == YES", server)
            trackRequest.fetchLimit = 50
            
            guard let cdTracks = try? context.fetch(trackRequest) else {
                return []
            }
            
            // Shuffle and limit to 50
            let shuffled = cdTracks.shuffled().prefix(50)
            
            return shuffled.map { cdTrack in
                CoreDataTrackHelper.toDomain(cdTrack, serverId: serverId)
            }
        }
        
        guard !tracks.isEmpty else {
            Self.logger.warning("playShuffleLiked: No liked tracks found")
            return
        }
        
        await MainActor.run {
            coordinator.playbackViewModel.startQueue(
                from: tracks,
                at: 0,
                context: .custom(tracks.map { $0.id })
            )
        }
    }
    
    private func playRecentlyPlayed() async {
        UIImpactFeedbackGenerator.medium()
        
        await MainActor.run {
            isLoading = true
        }
        
        defer {
            Task { @MainActor in
                isLoading = false
            }
        }
        
        do {
            let tracks = try await coordinator.libraryRepository.fetchRecentlyPlayed(limit: 50)
            
            guard !tracks.isEmpty else {
                Self.logger.warning("playRecentlyPlayed: No recently played tracks")
                return
            }
            
            await MainActor.run {
                coordinator.playbackViewModel.startQueue(
                    from: tracks,
                    at: 0,
                    context: .custom(tracks.map { $0.id })
                )
            }
        } catch {
            Self.logger.error("playRecentlyPlayed: Error: \(error.localizedDescription)")
        }
    }
    
    private func playGenre(_ umbrellaGenre: String) async {
        UIImpactFeedbackGenerator.light()
        
        await MainActor.run {
            isLoading = true
        }
        
        defer {
            Task { @MainActor in
                isLoading = false
            }
        }
        
        guard let serverId = coordinator.activeServer?.id else {
            Self.logger.warning("playGenre: No active server")
            return
        }
        
        let context = viewContext
        let tracks: [Track] = await context.perform {
            // Find server
            let serverRequest: NSFetchRequest<CDServer> = CDServer.fetchRequest()
            serverRequest.predicate = NSPredicate(format: "id == %@", serverId as CVarArg)
            serverRequest.fetchLimit = 1
            
            guard let server = try? context.fetch(serverRequest).first else {
                return []
            }
            
            // Fetch all tracks for this server
            let trackRequest: NSFetchRequest<CDTrack> = CDTrack.fetchRequest()
            trackRequest.predicate = NSPredicate(format: "server == %@", server)
            
            guard let allTracks = try? context.fetch(trackRequest) else {
                return []
            }
            
            // Filter tracks that have this umbrella genre
            let genreTracks = allTracks.filter { cdTrack in
                guard let umbrellaGenres = cdTrack.umbrellaGenres as? [String] else {
                    return false
                }
                return umbrellaGenres.contains(umbrellaGenre)
            }
            
            // Shuffle and limit to 50
            let shuffled = genreTracks.shuffled().prefix(50)
            
            return shuffled.map { cdTrack in
                CoreDataTrackHelper.toDomain(cdTrack, serverId: serverId)
            }
        }
        
        guard !tracks.isEmpty else {
            Self.logger.warning("playGenre: No tracks found for genre \(umbrellaGenre)")
            return
        }
        
        await MainActor.run {
            coordinator.playbackViewModel.startQueue(
                from: tracks,
                at: 0,
                context: .custom(tracks.map { $0.id })
            )
        }
    }
    
    private func playRecentlyAdded() async {
        UIImpactFeedbackGenerator.medium()
        
        await MainActor.run {
            isLoading = true
        }
        
        defer {
            Task { @MainActor in
                isLoading = false
            }
        }
        
        guard coordinator.activeServer?.id != nil else {
            Self.logger.warning("playRecentlyAdded: No active server")
            return
        }
        
        do {
            // Fetch recently added tracks from API (this will also sync missing metadata)
            let tracks = try await coordinator.libraryRepository.fetchRecentlyAdded(limit: 500)
            
            guard !tracks.isEmpty else {
                Self.logger.warning("playRecentlyAdded: No recently added tracks")
                return
            }
            
            // Sort tracks by dateAdded descending (most recent first)
            let sortedTracks = tracks.sorted { track1, track2 in
                let date1 = track1.dateAdded ?? Date.distantPast
                let date2 = track2.dateAdded ?? Date.distantPast
                return date1 > date2
            }
            
            await MainActor.run {
                coordinator.playbackViewModel.startQueue(
                    from: sortedTracks,
                    at: 0,
                    context: .custom(sortedTracks.map { $0.id })
                )
            }
        } catch {
            Self.logger.error("playRecentlyAdded: Error: \(error.localizedDescription)")
        }
    }
    
    private func playShuffleAll() async {
        UIImpactFeedbackGenerator.medium()
        
        await MainActor.run {
            isLoading = true
        }
        
        defer {
            Task { @MainActor in
                isLoading = false
            }
        }
        
        guard coordinator.activeServer?.id != nil else {
            Self.logger.warning("playShuffleAll: No active server")
            return
        }
        
        do {
            // Fetch all tracks from library
            let allTracks = try await coordinator.libraryRepository.fetchTracks(albumId: nil)
            
            guard !allTracks.isEmpty else {
                Self.logger.warning("playShuffleAll: No tracks found")
                return
            }
            
            // Shuffle and limit to 500 for performance
            let shuffled = allTracks.shuffled().prefix(500)
            let tracks = Array(shuffled)
            
            await MainActor.run {
                coordinator.playbackViewModel.startQueue(
                    from: tracks,
                    at: 0,
                    context: .custom(tracks.map { $0.id })
                )
            }
        } catch {
            Self.logger.error("playShuffleAll: Error: \(error.localizedDescription)")
        }
    }
    
    private func refreshLikedTracks() async {
        UIImpactFeedbackGenerator.light()
        
        await MainActor.run {
            isLoading = true
        }
        
        defer {
            Task { @MainActor in
                isLoading = false
                // Reload liked count after refresh
                Task {
                    await loadLikedCount()
                }
            }
        }
        
        do {
            // Sync liked tracks from server
            try await coordinator.libraryRepository.syncLikedTracks()
            Self.logger.info("refreshLikedTracks: Successfully synced liked tracks")
        } catch {
            Self.logger.error("refreshLikedTracks: Error: \(error.localizedDescription)")
        }
    }
}

// MARK: - Hero Section

struct HeroSection: View {
    let likedCount: Int
    let isLoading: Bool
    let onShuffleLiked: () async -> Void
    let onRecentlyPlayed: () async -> Void
    let onRecentlyAdded: () async -> Void
    let onShuffleAll: () async -> Void
    let onRefreshLiked: () async -> Void
    
    var body: some View {
        VStack(spacing: 12) {
            // Shuffle Liked with Refresh button inside
            Button(action: {
                Task {
                    await onShuffleLiked()
                }
            }) {
                HStack(spacing: 12) {
                    Image(systemName: "shuffle")
                        .font(.system(size: 20, weight: .semibold))
                        .frame(width: 32, height: 32)
                        .background(Color("AppAccent").opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Shuffle Liked")
                            .font(.headline)
                            .foregroundStyle(Color("AppTextPrimary"))
                        if likedCount > 0 {
                            Text("Random from \(likedCount) tracks")
                                .font(.subheadline)
                                .foregroundStyle(Color("AppTextSecondary"))
                        }
                    }
                    
                    Spacer()
                    
                    // Refresh button inside
                    Button(action: {
                        Task {
                            await onRefreshLiked()
                        }
                    }) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Color("AppAccent"))
                            .frame(width: 32, height: 32)
                            .background(Color("AppAccent").opacity(0.1))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .disabled(isLoading)
                    
                    if isLoading {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle())
                            .scaleEffect(0.8)
                    } else {
                        Image(systemName: "chevron.right")
                            .font(.subheadline)
                            .foregroundStyle(Color("AppTextSecondary"))
                    }
                }
                .padding(14)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 18))
            }
            .buttonStyle(.plain)
            .disabled(isLoading)
            
            PrimaryActionButton(
                title: "Recently Played",
                subtitle: "Last 50 tracks",
                systemImage: "clock.arrow.circlepath",
                isLoading: isLoading
            ) {
                await onRecentlyPlayed()
            }
            
            PrimaryActionButton(
                title: "Recently Added",
                subtitle: "500 most recent tracks",
                systemImage: "plus.circle.fill",
                isLoading: isLoading
            ) {
                await onRecentlyAdded()
            }
            
            PrimaryActionButton(
                title: "Shuffle All",
                subtitle: "Random from your entire library",
                systemImage: "shuffle",
                isLoading: isLoading
            ) {
                await onShuffleAll()
            }
        }
    }
}

// MARK: - Genres Section

struct GenresSection: View {
    let genres: [String]
    let genreCounts: [String: Int]
    let isLoading: Bool
    let onGenreTap: (String) async -> Void
    
    let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Genres")
                .font(.title2)
                .fontWeight(.semibold)
                .padding(.top, 4)
            
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(genres, id: \.self) { genre in
                    GenreCardView(
                        genre: genre,
                        count: genreCounts[genre] ?? 0,
                        isLoading: isLoading
                    ) {
                        await onGenreTap(genre)
                    }
                }
            }
        }
    }
}

// MARK: - Primary Action Button

struct PrimaryActionButton: View {
    let title: String
    let subtitle: String?
    let systemImage: String
    let isLoading: Bool
    let action: () async -> Void
    
    var body: some View {
        Button(action: {
            Task {
                await action()
            }
        }) {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .font(.system(size: 20, weight: .semibold))
                    .frame(width: 32, height: 32)
                    .background(Color("AppAccent").opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(Color("AppTextPrimary"))
                    if let subtitle {
                        Text(subtitle)
                            .font(.subheadline)
                            .foregroundStyle(Color("AppTextSecondary"))
                    }
                }
                
                Spacer()
                
                if isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle())
                        .scaleEffect(0.8)
                } else {
                    Image(systemName: "chevron.right")
                        .font(.subheadline)
                        .foregroundStyle(Color("AppTextSecondary"))
                }
            }
            .padding(14)
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 18))
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
    }
}

// MARK: - Genre Card View

struct GenreCardView: View {
    let genre: String
    let count: Int
    let isLoading: Bool
    let action: () async -> Void
    
    var body: some View {
        Button(action: {
            Task {
                await action()
            }
        }) {
            HStack(spacing: 8) {
                Image(systemName: iconForGenre(genre))
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(colorForGenre(genre).opacity(0.8))
                
                Text(genre)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color("AppTextPrimary"))
                    .lineLimit(1)
                
                Spacer()
                
                if isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle())
                        .scaleEffect(0.7)
                }
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
            .background(colorForGenre(genre))
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
    }
    
    private func colorForGenre(_ genre: String) -> Color {
        switch genre {
        case "Electronic":
            return Color.blue.opacity(0.15)
        case "Rock":
            return Color.red.opacity(0.15)
        case "Hip-Hop":
            return Color.orange.opacity(0.15)
        case "Pop":
            return Color.pink.opacity(0.15)
        case "Jazz":
            return Color.purple.opacity(0.15)
        case "Classical":
            return Color.indigo.opacity(0.15)
        case "Country":
            return Color.green.opacity(0.15)
        case "R&B":
            return Color.mint.opacity(0.15)
        case "Metal":
            return Color.gray.opacity(0.15)
        case "Punk":
            return Color.red.opacity(0.2)
        case "Blues":
            return Color.blue.opacity(0.2)
        case "Folk":
            return Color.brown.opacity(0.15)
        case "Reggae":
            return Color.green.opacity(0.2)
        case "Latin":
            return Color.orange.opacity(0.2)
        case "Soundtrack":
            return Color.purple.opacity(0.2)
        case "World":
            return Color.cyan.opacity(0.15)
        default:
            return Color.gray.opacity(0.15)
        }
    }
    
    private func iconForGenre(_ genre: String) -> String {
        switch genre {
        case "Electronic":
            return "waveform"
        case "Rock":
            return "guitars"
        case "Hip-Hop":
            return "hifispeaker.fill"
        case "Pop":
            return "music.note.list"
        case "Jazz":
            return "music.quarternote.3"
        case "Classical":
            return "pianokeys"
        case "Country":
            return "guitar"
        case "R&B":
            return "music.note"
        case "Metal":
            return "flame"
        case "Punk":
            return "exclamationmark.triangle"
        case "Blues":
            return "music.mic"
        case "Folk":
            return "music.quarternote.3"
        case "Reggae":
            return "music.note.tv"
        case "Latin":
            return "music.note"
        case "Soundtrack":
            return "tv"
        case "World":
            return "globe"
        default:
            return "music.note"
        }
    }
}

// MARK: - Library Scan Indicator

struct LibraryScanIndicator: View {
    let progress: Double
    let stage: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color("AppAccent"))
                
                Text("Library Scan")
                    .font(.headline)
                    .foregroundStyle(Color("AppTextPrimary"))
                
                Spacer()
                
                Text("\(Int(progress * 100))%")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(Color("AppTextSecondary"))
            }
            
            ProgressView(value: progress)
                .progressViewStyle(LinearProgressViewStyle(tint: Color("AppAccent")))
            
            Text(stage)
                .font(.caption)
                .foregroundStyle(Color("AppTextSecondary"))
        }
        .padding(16)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

// MARK: - No Genres Message

struct NoGenresMessage: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "music.note.list")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Color("AppTextSecondary"))
                
                Text("Genres")
                    .font(.title2)
                    .fontWeight(.semibold)
            }
            .padding(.top, 4)
            
            VStack(spacing: 12) {
                Image(systemName: "info.circle")
                    .font(.system(size: 32))
                    .foregroundStyle(Color("AppTextSecondary").opacity(0.6))
                
                Text("No genres available")
                    .font(.headline)
                    .foregroundStyle(Color("AppTextPrimary"))
                
                Text("Your music library doesn't have genre metadata. Genres will appear here automatically once your tracks are tagged with genre information in your media server.")
                    .font(.subheadline)
                    .foregroundStyle(Color("AppTextSecondary"))
                    .multilineTextAlignment(.center)
                    .lineLimit(nil)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
            .padding(.horizontal, 16)
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
    }
}

