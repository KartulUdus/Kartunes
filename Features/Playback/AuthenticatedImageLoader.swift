
import SwiftUI
import UIKit

/// Custom image loader for authenticated Emby/Jellyfin album art
/// Uses URLSession to properly handle authenticated requests
struct AuthenticatedImageLoader: View {
    private static let logger = Log.make(.playback)
    
    let url: URL?
    @State private var imageData: Data?
    @State private var isLoading = false
    @State private var currentURL: URL?
    @State private var loadError: Error?
    
    var body: some View {
        Group {
            if let imageData = imageData, let uiImage = UIImage(data: imageData) {
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else if isLoading {
                ProgressView()
            } else {
                Color.clear
            }
        }
        .onChange(of: url?.absoluteString) { oldValue, newURLString in
            // Reset when URL changes
            if newURLString != currentURL?.absoluteString {
                imageData = nil
                currentURL = nil
                loadError = nil
            }
        }
        .task(id: url?.absoluteString) {
            guard let url = url else {
                imageData = nil
                currentURL = nil
                return
            }
            
            // Only load if URL changed or we don't have data
            if url.absoluteString != currentURL?.absoluteString || imageData == nil {
                await loadImage(from: url)
            }
        }
    }
    
    private func loadImage(from url: URL) async {
        isLoading = true
        loadError = nil
        currentURL = url
        defer { isLoading = false }
        
        do {
            var request = URLRequest(url: url)
            request.cachePolicy = .returnCacheDataElseLoad
            request.timeoutInterval = 10.0
            
            let (data, response) = try await URLSession.shared.data(for: request)
            
            // Check for HTTP errors
            if let httpResponse = response as? HTTPURLResponse {
                if httpResponse.statusCode != 200 {
                    throw NSError(domain: "ImageLoader", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "HTTP \(httpResponse.statusCode)"])
                }
            }
            
            // Verify it's actually image data
            guard UIImage(data: data) != nil else {
                throw NSError(domain: "ImageLoader", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid image data"])
            }
            
            await MainActor.run {
                self.imageData = data
                self.currentURL = url
                Self.logger.debug("Successfully loaded image from \(url.absoluteString)")
            }
        } catch {
            Self.logger.error("Failed to load image from \(url.absoluteString): \(error.localizedDescription)")
            await MainActor.run {
                self.imageData = nil
                self.loadError = error
            }
        }
    }
}

