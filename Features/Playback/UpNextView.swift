
import SwiftUI
import UIKit

struct UpNextView: View {
    @ObservedObject var viewModel: PlaybackViewModel
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var coordinator: AppCoordinator
    @State private var scrollTrigger = UUID()
    
    private var upNextTracks: [Track] {
        viewModel.getUpNextTracks()
    }
    
    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                List {
                    if upNextTracks.isEmpty {
                        Text("No upcoming tracks")
                            .foregroundStyle(Color("AppTextSecondary"))
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding()
                    } else {
                        ForEach(upNextTracks, id: \.id) { track in
                        let isCurrentlyPlaying = track.id == viewModel.currentTrack?.id
                        
                        Button(action: {
                            UIImpactFeedbackGenerator.medium()
                            // Skip to this track
                            // Find the track's index in the original queue
                            if let queueIndex = viewModel.queue.firstIndex(where: { $0.id == track.id }) {
                                viewModel.skipTo(index: queueIndex)
                            }
                            dismiss()
                        }) {
                            HStack(spacing: 12) {
                                // Speaker icon for currently playing track
                                if isCurrentlyPlaying {
                                    Image(systemName: "speaker.wave.2.fill")
                                        .font(.caption)
                                        .foregroundStyle(Color("AppAccent"))
                                        .frame(width: 20)
                                } else {
                                    Spacer()
                                        .frame(width: 20)
                                }
                                
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(track.title)
                                        .font(.headline)
                                        .foregroundStyle(isCurrentlyPlaying ? Color("AppAccent") : Color("AppTextPrimary"))
                                    
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
                                
                                // Download button
                                downloadButtonView(for: track)
                            }
                            .padding(.vertical, 4)
                        }
                        .buttonStyle(.plain)
                        .id(track.id) // Add ID for ScrollViewReader
                        .contextMenu {
                            downloadButton(for: track)
                        }
                    }
                }
                }
                .scrollContentBackground(.hidden)
                .background(Color("AppBackground"))
                .onAppear {
                    // Scroll to current track when view appears
                    if let currentTrackId = viewModel.currentTrack?.id {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            withAnimation {
                                proxy.scrollTo(currentTrackId, anchor: .center)
                            }
                        }
                    }
                }
                .onChange(of: scrollTrigger) { _, _ in
                    // Scroll when trigger changes (button pressed)
                    if let currentTrackId = viewModel.currentTrack?.id {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            withAnimation {
                                proxy.scrollTo(currentTrackId, anchor: .center)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Queue")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Scroll") {
                        UIImpactFeedbackGenerator.light()
                        // Trigger scroll by updating state
                        scrollTrigger = UUID()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        UIImpactFeedbackGenerator.light()
                        dismiss()
                    }
                }
            }
        }
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        guard duration.isFinite && !duration.isNaN && duration >= 0 else {
            return "0:00"
        }
        
        let totalSeconds = Int(duration.rounded())
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
    
    @ViewBuilder
    private func downloadButtonView(for track: Track) -> some View {
        let status = DownloadStatusManager.getStatus(for: track.id)
        let isDownloaded = OfflineDownloadManager.shared.isDownloaded(trackId: track.id)
        
        if status == .downloading || status == .queued {
            Button {
                OfflineDownloadManager.shared.cancelDownload(for: track.id)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(Color("AppTextSecondary"))
                    .font(.caption)
            }
            .buttonStyle(.plain)
        } else if status == .downloaded || isDownloaded {
            Button {
                Task {
                    do {
                        try OfflineDownloadManager.shared.deleteDownload(for: track.id)
                    } catch {
                        // Handle error
                    }
                }
            } label: {
                Image(systemName: "arrow.down.circle.fill")
                    .foregroundStyle(Color("AppAccent"))
                    .font(.caption)
            }
            .buttonStyle(.plain)
        } else {
            Button {
                Task {
                    guard let apiClient = coordinator.apiClient else { return }
                    await OfflineDownloadManager.shared.startDownload(
                        for: track,
                        apiClient: apiClient,
                        progressCallback: { progress in
                            NotificationCenter.default.post(
                                name: .downloadProgress,
                                object: nil,
                                userInfo: ["trackId": track.id, "progress": progress]
                            )
                        }
                    )
                }
            } label: {
                Image(systemName: "arrow.down.circle")
                    .foregroundStyle(Color("AppAccent"))
                    .font(.caption)
            }
            .buttonStyle(.plain)
        }
    }
    
    @ViewBuilder
    private func downloadButton(for track: Track) -> some View {
        let status = DownloadStatusManager.getStatus(for: track.id)
        let isDownloaded = OfflineDownloadManager.shared.isDownloaded(trackId: track.id)
        
        if status == .downloading || status == .queued {
            Button {
                OfflineDownloadManager.shared.cancelDownload(for: track.id)
            } label: {
                Label("Cancel Download", systemImage: "xmark.circle")
            }
        } else if status == .downloaded || isDownloaded {
            Button(role: .destructive) {
                Task {
                    do {
                        try OfflineDownloadManager.shared.deleteDownload(for: track.id)
                    } catch {
                        // Handle error
                    }
                }
            } label: {
                Label("Remove Download", systemImage: "trash")
            }
        } else {
            Button {
                Task {
                    guard let apiClient = coordinator.apiClient else { return }
                    await OfflineDownloadManager.shared.startDownload(
                        for: track,
                        apiClient: apiClient,
                        progressCallback: { progress in
                            NotificationCenter.default.post(
                                name: .downloadProgress,
                                object: nil,
                                userInfo: ["trackId": track.id, "progress": progress]
                            )
                        }
                    )
                }
            } label: {
                Label("Download Offline", systemImage: "arrow.down.circle")
            }
        }
    }
}

