
import SwiftUI
import UIKit
import OSLog

/// Custom image loader for authenticated Jellyfin album art
struct AlbumArtImage: View {
    private static let logger = Logger(subsystem: "com.kartunes.app", category: "Watch")
    
    let url: URL?
    @State private var imageData: Data?
    @State private var isLoading = false
    @State private var currentURL: URL?
    
    var body: some View {
        GeometryReader { geometry in
            Group {
                if let imageData = imageData, let uiImage = UIImage(data: imageData) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .aspectRatio(1, contentMode: .fit)
                        .frame(width: geometry.size.height, height: geometry.size.height)
                        .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
                } else if isLoading {
                    Color.black.opacity(0.3)
                } else {
                    Color.black.opacity(0.3)
                }
            }
        }
        .onChange(of: url) { oldValue, newURL in
            // Reset image data when URL changes
            if newURL != currentURL {
                imageData = nil
                currentURL = newURL
            }
        }
        .task(id: url?.absoluteString) {
            guard let url = url else {
                imageData = nil
                currentURL = nil
                return
            }
            
            // Only load if URL changed or we don't have data
            if url != currentURL || imageData == nil {
                await loadImage(from: url)
            }
        }
    }
    
    private func loadImage(from url: URL) async {
        isLoading = true
        defer { isLoading = false }
        
        do {
            var request = URLRequest(url: url)
            request.cachePolicy = .returnCacheDataElseLoad
            
            let (data, _) = try await URLSession.shared.data(for: request)
            await MainActor.run {
                self.imageData = data
                self.currentURL = url
            }
        } catch {
            Self.logger.error("Failed to load image from \(url): \(error.localizedDescription)")
            await MainActor.run {
                self.imageData = nil
            }
        }
    }
}

