
import SwiftUI

struct WatchNowPlayingView: View {
    @StateObject private var viewModel: WatchPlaybackViewModel
    
    init() {
        let session = WatchPlaybackSession()
        let viewModel = WatchPlaybackViewModel(session: session)
        _viewModel = StateObject(wrappedValue: viewModel)
    }
    
    var body: some View {
        ZStack {
            // Album Art Background
            Group {
                if let albumArtURL = viewModel.albumArtURL, viewModel.hasTrack {
                    AlbumArtImage(url: albumArtURL)
                        .ignoresSafeArea()
                        .overlay(
                            // Subtle dark overlay for text readability
                            LinearGradient(
                                colors: [Color.black.opacity(0.3), Color.black.opacity(0.2)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                } else {
                    // Default background when no art
                    Color.black.opacity(0.3)
                        .ignoresSafeArea()
                }
            }
            
            // Content - Organized in distinct sections
            VStack(spacing: 0) {
                // Top Section: Like and Radio Buttons
                if viewModel.hasTrack {
                    HStack {
                        // Heart Button - Left
                        Button(action: {
                            viewModel.toggleFavourite()
                        }) {
                            Image(systemName: viewModel.isFavourite ? "heart.fill" : "heart")
                                .font(.title2)
                                .foregroundColor(Color("AppAccent"))
                                .shadow(color: .black.opacity(0.5), radius: 2, x: 0, y: 1)
                        }
                        .buttonStyle(.plain)
                        
                        Spacer()
                        
                        // Radio Button - Right
                        Button(action: {
                            viewModel.radioTapped()
                        }) {
                            Image(systemName: "radio")
                                .font(.title2)
                                .foregroundColor(Color("AppAccent"))
                                .shadow(color: .black.opacity(0.5), radius: 2, x: 0, y: 1)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
                    .padding(.bottom, 4)
                }
                
                Spacer()
                
                // Middle Section: Track Info - Centered with padding to avoid overlap
                if viewModel.hasTrack {
                    VStack(spacing: 4) {
                        Text(viewModel.trackTitle)
                            .font(.headline)
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                            .foregroundColor(Color("AppAccent"))
                            .shadow(color: .black.opacity(0.5), radius: 2, x: 0, y: 1)
                        
                        Text(viewModel.trackArtist)
                            .font(.caption)
                            .lineLimit(1)
                            .foregroundColor(Color("AppAccent"))
                            .shadow(color: .black.opacity(0.5), radius: 2, x: 0, y: 1)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color("AppOverlay").opacity(0.7))
                    .cornerRadius(8)
                } else {
                    VStack(spacing: 4) {
                        Text("Nothing Playing")
                            .font(.headline)
                            .foregroundColor(Color("AppTextSecondary"))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
                
                Spacer()
                
                // Bottom Section: Transport Controls
                HStack(spacing: 20) {
                    // Previous (Skip Previous)
                    Button(action: {
                        viewModel.previousTapped()
                    }) {
                        Image(systemName: "backward.end.fill")
                            .font(.title2)
                            .foregroundColor(Color("AppAccent"))
                    }
                    .buttonStyle(.bordered)
                    .tint(Color("AppAccent").opacity(0.3))
                    .disabled(!viewModel.hasTrack)
                    
                    // Play/Pause
                    Button(action: {
                        viewModel.playPauseTapped()
                    }) {
                        Image(systemName: viewModel.isPlaying ? "pause.fill" : "play.fill")
                            .font(.title)
                            .foregroundColor(.black)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color("AppAccent"))
                    .disabled(!viewModel.hasTrack)
                    
                    // Next (Skip Next)
                    Button(action: {
                        viewModel.nextTapped()
                    }) {
                        Image(systemName: "forward.end.fill")
                            .font(.title2)
                            .foregroundColor(Color("AppAccent"))
                    }
                    .buttonStyle(.bordered)
                    .tint(Color("AppAccent").opacity(0.3))
                    .disabled(!viewModel.hasTrack)
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
            }
        }
        .task {
            // Request state as soon as the view is visible
            viewModel.session.requestState()
            // Also try after a short delay in case session wasn't ready; this task cancels automatically on disappear
            try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
            if !Task.isCancelled {
                viewModel.session.requestState()
            }
        }
    }
}

#Preview {
    WatchNowPlayingView()
}
