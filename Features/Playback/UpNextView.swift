
import SwiftUI
import UIKit

struct UpNextView: View {
    @ObservedObject var viewModel: PlaybackViewModel
    @Environment(\.dismiss) var dismiss
    
    private var upNextTracks: [Track] {
        viewModel.getUpNextTracks()
    }
    
    var body: some View {
        NavigationStack {
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
                                
                                Text(formatDuration(track.duration))
                                    .font(.caption)
                                    .foregroundStyle(Color("AppTextSecondary"))
                            }
                            .padding(.vertical, 4)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color("AppBackground"))
            .navigationTitle("Queue")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
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
}

