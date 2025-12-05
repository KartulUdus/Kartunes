
import SwiftUI
import UIKit

struct MiniPlayerView: View {
    @ObservedObject var viewModel: PlaybackViewModel
    @State private var showNowPlaying = false
    @State private var showUpNext = false
    @State private var albumArtImage: UIImage?
    
    var body: some View {
        if viewModel.currentTrack != nil {
            HStack(spacing: 10) {
                // Up Next Button (only show if there are upcoming tracks)
                if !viewModel.getUpNextTracks().isEmpty {
                    Button(action: {
                        UIImpactFeedbackGenerator.light()
                        showUpNext = true
                    }) {
                        Image(systemName: "list.bullet")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(Color("AppTextPrimary"))
                    }
                    .buttonStyle(.plain)
                }
                
                // Tappable area for track info - opens NowPlaying
                // Make the entire area tappable by using a ZStack with a transparent button
                Button(action: {
                    UIImpactFeedbackGenerator.light()
                    showNowPlaying = true
                }) {
                    HStack(spacing: 10) {
                        // Album Art
                        Group {
                            if let image = albumArtImage {
                                Image(uiImage: image)
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                            } else {
                                Rectangle()
                                    .fill(
                                        LinearGradient(
                                            colors: [Color.blue.opacity(0.5), Color.purple.opacity(0.5)],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    .overlay(
                                        Image(systemName: "music.note")
                                            .foregroundStyle(Color("AppTextPrimary").opacity(0.7))
                                            .font(.system(size: 16))
                                    )
                            }
                        }
                        .frame(width: 40, height: 40)
                        .cornerRadius(8)
                        .clipped()
                        
                        // Track Info
                        VStack(alignment: .leading, spacing: 2) {
                            Text(viewModel.currentTrack?.title ?? "Unknown Track")
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundStyle(Color("AppTextPrimary"))
                                .lineLimit(1)
                            Text(viewModel.currentTrack?.artistName ?? "Unknown Artist")
                                .font(.caption2)
                                .foregroundStyle(Color("AppTextSecondary"))
                                .lineLimit(1)
                        }
                        
                        Spacer() // Push content to left, make rest of area tappable
                    }
                    .contentShape(Rectangle()) // Makes entire area tappable
                }
                .buttonStyle(.plain)
                
                // Stop Button
                Button(action: {
                    UIImpactFeedbackGenerator.medium()
                    viewModel.stop()
                }) {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color("AppTextPrimary"))
                }
                .buttonStyle(.plain)
                
                // Spacing between Stop and Play buttons
                Spacer()
                    .frame(width: 2)
                
                // Play/Pause Button
                Button(action: {
                    UIImpactFeedbackGenerator.medium()
                    viewModel.togglePlayPause()
                }) {
                    Image(systemName: viewModel.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color("AppTextPrimary"))
                }
                .buttonStyle(.plain)
                Spacer()
                    .frame(width: 2)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(Color("AppCardBackground"))
                    .shadow(color: Color("AppBackground").opacity(0.3), radius: 8, x: 0, y: 2)
            )
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .sheet(isPresented: $showNowPlaying) {
                NavigationStack {
                    NowPlayingView(viewModel: viewModel)
                }
            }
            .sheet(isPresented: $showUpNext) {
                UpNextView(viewModel: viewModel)
            }
            .onChange(of: viewModel.currentTrack?.id) { oldValue, newTrackId in
                if newTrackId != oldValue {
                    albumArtImage = nil
                    loadAlbumArt()
                }
            }
            .onAppear {
                loadAlbumArt()
            }
        }
    }
    
    private func loadAlbumArt() {
        guard let track = viewModel.currentTrack else {
            albumArtImage = nil
            return
        }
        
        // Get image URL - prefer track ID for Emby
        let imageURL: URL? = {
            // Try track ID first (Emby often has images on tracks)
            if let url = viewModel.buildTrackImageURL(trackId: track.id, albumId: track.albumId) {
                return url
            }
            // Fallback to album ID
            if let albumId = track.albumId,
               let url = viewModel.albumArtURL(for: albumId) {
                return url
            }
            return nil
        }()
        
        guard let imageURL = imageURL else {
            albumArtImage = nil
            return
        }
        
        Task {
            do {
                var request = URLRequest(url: imageURL)
                request.cachePolicy = .returnCacheDataElseLoad
                request.timeoutInterval = 10.0
                
                let (data, response) = try await URLSession.shared.data(for: request)
                
                // Check for HTTP errors
                if let httpResponse = response as? HTTPURLResponse {
                    if httpResponse.statusCode != 200 {
                        await MainActor.run {
                            albumArtImage = nil
                        }
                        return
                    }
                }
                
                // Verify it's actually image data
                guard let uiImage = UIImage(data: data) else {
                    await MainActor.run {
                        albumArtImage = nil
                    }
                    return
                }
                
                await MainActor.run {
                    albumArtImage = uiImage
                }
            } catch {
                await MainActor.run {
                    albumArtImage = nil
                }
            }
        }
    }
}
