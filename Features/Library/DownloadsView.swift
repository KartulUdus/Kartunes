import SwiftUI
import CoreData

struct DownloadsView: View {
    @EnvironmentObject var coordinator: AppCoordinator
    @Environment(\.managedObjectContext) private var viewContext
    @State private var downloadedTracks: [Track] = []
    @State private var downloadingTracks: [Track] = []
    @State private var downloadProgress: [String: Double] = [:]
    @State private var selectedTrack: Track?
    @State private var showingDeleteConfirmation = false
    @State private var trackToDelete: Track?
    @State private var isLoading = true
    
    private var activeServer: CDServer? {
        guard let serverId = coordinator.activeServer?.id else { return nil }
        let request: NSFetchRequest<CDServer> = CDServer.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", serverId as CVarArg)
        request.fetchLimit = 1
        return try? viewContext.fetch(request).first
    }
    
    var body: some View {
        List {
            if isLoading {
                ProgressView("Loading downloads...")
            } else if downloadedTracks.isEmpty && downloadingTracks.isEmpty {
                Text("No downloads")
                    .foregroundStyle(Color("AppTextSecondary"))
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding()
            } else {
                // Play All button
                if !downloadedTracks.isEmpty {
                    Section {
                        Button(action: {
                            coordinator.playbackViewModel.startQueue(
                                from: downloadedTracks,
                                at: 0,
                                context: .offlineDownloads
                            )
                        }) {
                            HStack {
                                Image(systemName: "play.circle.fill")
                                    .font(.title2)
                                    .foregroundStyle(Color("AppAccent"))
                                Text("Play All Offline")
                                    .font(.headline)
                                    .foregroundStyle(Color("AppTextPrimary"))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(Color("AppCardBackground").opacity(0.3))
                        
                        Button(action: {
                            coordinator.playbackViewModel.startQueue(
                                from: downloadedTracks.shuffled(),
                                at: 0,
                                context: .offlineDownloads
                            )
                            coordinator.playbackViewModel.toggleShuffle()
                        }) {
                            HStack {
                                Image(systemName: "shuffle")
                                    .font(.title2)
                                    .foregroundStyle(Color("AppAccent"))
                                Text("Shuffle Offline")
                                    .font(.headline)
                                    .foregroundStyle(Color("AppTextPrimary"))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(Color("AppCardBackground").opacity(0.3))
                    }
                }
                
                // Downloading section
                if !downloadingTracks.isEmpty {
                    Section(header: Text("Downloading")) {
                        ForEach(downloadingTracks, id: \.id) { track in
                            DownloadingTrackRow(
                                track: track,
                                progress: downloadProgress[track.id] ?? 0.0,
                                onCancel: {
                                    OfflineDownloadManager.shared.cancelDownload(for: track.id)
                                    Task {
                                        await refreshDownloads()
                                    }
                                }
                            )
                        }
                    }
                }
                
                // Downloaded section
                if !downloadedTracks.isEmpty {
                    Section(header: Text("Downloaded")) {
                        ForEach(downloadedTracks, id: \.id) { track in
                            DownloadedTrackRow(
                                track: track,
                                onTap: {
                                    // Play from local file - build queue from all downloaded tracks
                                    if let index = downloadedTracks.firstIndex(where: { $0.id == track.id }) {
                                        coordinator.playbackViewModel.startQueue(
                                            from: downloadedTracks,
                                            at: index,
                                            context: .offlineDownloads
                                        )
                                    }
                                },
                                onDelete: {
                                    trackToDelete = track
                                    showingDeleteConfirmation = true
                                }
                            )
                        }
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Color("AppBackground"))
        .contentMargins(.top, 0, for: .scrollContent)
        .safeAreaInset(edge: .bottom) {
            Spacer()
                .frame(height: coordinator.playbackViewModel.currentTrack != nil ? 100 : 0)
        }
        .navigationTitle("Downloads")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await refreshDownloads()
        }
        .onReceive(NotificationCenter.default.publisher(for: .downloadProgress)) { notification in
            if let trackId = notification.userInfo?["trackId"] as? String,
               let progress = notification.userInfo?["progress"] as? Double {
                downloadProgress[trackId] = progress
                Task {
                    await refreshDownloads()
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .downloadStarted)) { _ in
            Task {
                await refreshDownloads()
            }
        }
        .alert("Remove download?", isPresented: $showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) {
                trackToDelete = nil
            }
            Button("Remove", role: .destructive) {
                if let track = trackToDelete {
                    Task {
                        do {
                            try OfflineDownloadManager.shared.deleteDownload(for: track.id)
                            await refreshDownloads()
                        } catch {
                            // Handle error
                        }
                    }
                }
                trackToDelete = nil
            }
        } message: {
            Text("This will delete the offline file, but keep it in your library.")
        }
    }
    
    private func refreshDownloads() async {
        isLoading = true
        
        guard let serverId = coordinator.activeServer?.id else {
            isLoading = false
            return
        }
        
        let context = CoreDataStack.shared.viewContext
        let allDownloadedIds = Set(OfflineDownloadManager.shared.getAllDownloadedTrackIds())
        
        let tracks: [Track] = await context.perform {
            guard let server = try? CoreDataServerHelper.findBy(id: serverId, in: context) else {
                return []
            }
            
            let request: NSFetchRequest<CDTrack> = CDTrack.fetchRequest()
            request.predicate = NSPredicate(format: "server == %@ AND id IN %@", server, allDownloadedIds)
            
            guard let cdTracks = try? context.fetch(request) else {
                return []
            }
            
            return cdTracks.map { cdTrack in
                CoreDataTrackHelper.toDomain(cdTrack, serverId: serverId)
            }
        }
        
        // Separate downloaded and downloading tracks
        var downloaded: [Track] = []
        var downloading: [Track] = []
        
        // Also check for tracks that are downloading but not yet in Core Data
        // (in case download started before track was synced)
        let allDownloadingIds = DownloadStatusManager.getTrackIds(with: .downloading)
        let allQueuedIds = DownloadStatusManager.getTrackIds(with: .queued)
        let allDownloadingOrQueuedIds = Set(allDownloadingIds + allQueuedIds)
        
        // Get tracks from Core Data that match downloaded files
        for track in tracks {
            let status = DownloadStatusManager.getStatus(for: track.id)
            if status == .downloading || status == .queued {
                downloading.append(track)
            } else if status == .downloaded || OfflineDownloadManager.shared.isDownloaded(trackId: track.id) {
                downloaded.append(track)
            }
        }
        
        // Also add tracks that are downloading/queued but not in the tracks list
        // (they might be from a different server or not yet synced)
        let existingTrackIds = Set(tracks.map { $0.id })
        let missingDownloadingIds = allDownloadingOrQueuedIds.subtracting(existingTrackIds)
        
        // For missing downloading tracks, try to fetch them from Core Data
        if !missingDownloadingIds.isEmpty {
            NSLog("DownloadsView: Found \(missingDownloadingIds.count) downloading tracks not in current list, fetching from Core Data...")
            let missingTracks: [Track] = await context.perform {
                guard let server = try? CoreDataServerHelper.findBy(id: serverId, in: context) else {
                    return []
                }
                
                let request: NSFetchRequest<CDTrack> = CDTrack.fetchRequest()
                request.predicate = NSPredicate(format: "server == %@ AND id IN %@", server, Array(missingDownloadingIds))
                
                guard let cdTracks = try? context.fetch(request) else {
                    return []
                }
                
                return cdTracks.map { cdTrack in
                    CoreDataTrackHelper.toDomain(cdTrack, serverId: serverId)
                }
            }
            
            // Add missing tracks to downloading list
            for track in missingTracks {
                let status = DownloadStatusManager.getStatus(for: track.id)
                if status == .downloading || status == .queued {
                    downloading.append(track)
                }
            }
        }
        
        // Sort by title
        downloaded.sort { $0.title.localizedCompare($1.title) == .orderedAscending }
        downloading.sort { $0.title.localizedCompare($1.title) == .orderedAscending }
        
        await MainActor.run {
            downloadedTracks = downloaded
            downloadingTracks = downloading
            isLoading = false
        }
    }
}

struct DownloadingTrackRow: View {
    let track: Track
    let progress: Double
    let onCancel: () -> Void
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(track.title)
                    .font(.headline)
                    .foregroundStyle(Color("AppTextPrimary"))
                
                Text(track.artistName)
                    .font(.caption)
                    .foregroundStyle(Color("AppTextSecondary"))
                
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
                    .tint(Color("AppAccent"))
            }
            
            Spacer()
            
            Button(action: onCancel) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(Color("AppTextSecondary"))
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
        .listRowBackground(Color("AppCardBackground").opacity(0.3))
    }
}

struct DownloadedTrackRow: View {
    let track: Track
    let onTap: () -> Void
    let onDelete: () -> Void
    
    var body: some View {
        HStack {
            Button(action: onTap) {
                HStack {
                    Image(systemName: "arrow.down.circle.fill")
                        .foregroundStyle(Color("AppAccent"))
                        .font(.caption)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(track.title)
                            .font(.headline)
                            .foregroundStyle(Color("AppTextPrimary"))
                        
                        Text(track.artistName)
                            .font(.caption)
                            .foregroundStyle(Color("AppTextSecondary"))
                        
                        if let albumTitle = track.albumTitle {
                            Text(albumTitle)
                                .font(.caption2)
                                .foregroundStyle(Color("AppTextSecondary"))
                        }
                    }
                    
                    Spacer()
                }
            }
            .buttonStyle(.plain)
            
            Button(action: onDelete) {
                Image(systemName: "trash")
                    .foregroundStyle(Color("AppTextSecondary"))
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
        .listRowBackground(Color("AppCardBackground").opacity(0.3))
    }
}

extension Notification.Name {
    static let downloadProgress = Notification.Name("downloadProgress")
    static let downloadStarted = Notification.Name("downloadStarted")
}


