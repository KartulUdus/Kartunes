
import SwiftUI
import UIKit

struct NowPlayingView: View {
    private static let logger = Log.make(.nowPlaying)
    
    @ObservedObject var viewModel: PlaybackViewModel
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var isDragging = false
    @State private var dragValue: Double = 0
    @State private var isSeeking = false
    @State private var showUpNext = false
    @State private var albumArtImage: UIImage?
    @State private var isLoadingArt = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Album Art - Always show placeholder as base, overlay image when ready
            ZStack {
                // Base placeholder - always visible
                albumArtPlaceholder
                
                // Loading indicator overlay
                if isLoadingArt {
                    ProgressView()
                        .aspectRatio(1, contentMode: .fit)
                        .background(Color("AppSurface").opacity(0.8))
                }
                
                // Album art image overlay - only when loaded
                if let image = albumArtImage {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .aspectRatio(1, contentMode: .fit)
                        .clipped()
                        .overlay(
                            Color("AppBackground")
                                .opacity(colorScheme == .dark ? 0.4 : 0.2)
                        )
                        .transition(.opacity)
                }
            }
            .frame(maxWidth: .infinity)
            .animation(nil, value: viewModel.currentTrack?.id)
            .onChange(of: viewModel.currentTrack?.id) { oldValue, newTrackId in
                if newTrackId != oldValue {
                    // Don't clear image immediately - let it fade out naturally
                    // Start loading new image, which will replace the old one when ready
                    isLoadingArt = true
                    loadAlbumArt()
                }
            }
            .onAppear {
                loadAlbumArt()
            }
            
            // Track Info and Controls
            VStack(spacing: 20) {
                // Track Info with Like and Radio buttons
                HStack(spacing: 16) {
                    // Like Button (left)
                    if let track = viewModel.currentTrack {
                        Button(action: {
                            UIImpactFeedbackGenerator.light()
                            viewModel.toggleLike()
                        }) {
                            Image(systemName: track.isLiked ? "heart.fill" : "heart")
                                .font(.title3)
                                .foregroundStyle(track.isLiked ? Color("AppAccent") : Color("AppTextPrimary"))
                        }
                    }
                    
                    // Track Info (center)
                    VStack(spacing: 8) {
                        Text(viewModel.currentTrack?.title ?? "No Track")
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundStyle(Color("AppTextPrimary"))
                            .multilineTextAlignment(.center)
                        
                        Text(viewModel.currentTrack?.artistName ?? "Unknown Artist")
                            .font(.body)
                            .foregroundStyle(Color("AppTextSecondary"))
                            .multilineTextAlignment(.center)
                        
                        if let albumTitle = viewModel.currentTrack?.albumTitle {
                            Text(albumTitle)
                                .font(.caption)
                                .foregroundStyle(Color("AppTextSecondary"))
                        }
                    }
                    .frame(maxWidth: .infinity)
                    
                    // Radio Button (right)
                    if let track = viewModel.currentTrack {
                        VStack(spacing: 12) {
                            Button(action: {
                                UIImpactFeedbackGenerator.medium()
                                viewModel.startInstantMix(from: track.id)
                            }) {
                                Image(systemName: "radio")
                                    .font(.title3)
                                    .foregroundStyle(Color("AppTextPrimary"))
                            }
                            
                            // Up Next Button (below radio)
                            if !viewModel.getUpNextTracks().isEmpty {
                                Button(action: {
                                    UIImpactFeedbackGenerator.light()
                                    showUpNext.toggle()
                                }) {
                                    Image(systemName: "list.bullet")
                                        .font(.caption)
                                        .foregroundStyle(Color("AppTextPrimary"))
                                }
                                .padding(.top, 4)
                            }
                        }
                    }
                }
                .padding(.horizontal)
                
                // Scrubbable Progress Bar
                VStack(spacing: 4) {
                    // Use the drag value when dragging or seeking, otherwise use current time
                    let progressValue = (isDragging || isSeeking) ? dragValue : (viewModel.duration > 0 ? viewModel.currentTime / viewModel.duration : 0)
                    
                    // Custom slider that maintains pill shape and proper drag handling
                    CustomSlider(
                        value: Binding(
                            get: { progressValue },
                            set: { newValue in
                                dragValue = newValue
                                // Only seek immediately if not dragging (i.e., user tapped)
                                // When dragging, we'll seek in onEditingChanged when dragging ends
                                if !isDragging {
                                    isSeeking = true
                                    let seekTime = newValue * viewModel.duration
                                    viewModel.seek(to: seekTime)
                                    // Clear seeking flag after seek completes
                                    Task {
                                        try? await Task.sleep(nanoseconds: 200_000_000) // 0.2 seconds
                                        await MainActor.run {
                                            isSeeking = false
                                        }
                                    }
                                }
                            }
                        ),
                        in: 0...1,
                        onEditingChanged: { editing in
                            if editing {
                                // Started dragging - initialize drag value and prevent timer updates
                                isDragging = true
                                isSeeking = false
                                dragValue = viewModel.duration > 0 ? viewModel.currentTime / viewModel.duration : 0
                            } else {
                                // Finished dragging - seek to the final position
                                isDragging = false
                                isSeeking = true // Keep using dragValue during seek
                                let seekTime = dragValue * viewModel.duration
                                viewModel.seek(to: seekTime)
                                
                                // Clear seeking flag after a brief delay to allow seek to complete
                                Task {
                                    try? await Task.sleep(nanoseconds: 200_000_000) // 0.2 seconds
                                    await MainActor.run {
                                        isSeeking = false
                                    }
                                }
                            }
                        }
                    )
                    .frame(height: 44) // Standard slider height
                    
                    HStack {
                        Text(formatTime((isDragging || isSeeking) ? dragValue * viewModel.duration : viewModel.currentTime))
                            .font(.caption)
                            .foregroundStyle(Color("AppTextSecondary"))
                        
                        Spacer()
                        
                        Text(formatTime(viewModel.duration))
                            .font(.caption)
                            .foregroundStyle(Color("AppTextSecondary"))
                    }
                }
                .padding(.horizontal)
                
                // Playback Controls with Shuffle and Repeat
                HStack(spacing: 30) {
                    // Shuffle Button (left of previous)
                    Button(action: {
                        UIImpactFeedbackGenerator.light()
                        viewModel.toggleShuffle()
                    }) {
                        Image(systemName: "shuffle")
                            .font(.title3)
                            .foregroundStyle(viewModel.isShuffleEnabled ? Color("AppAccent") : Color("AppTextPrimary"))
                    }
                    .disabled(viewModel.currentTrack == nil)
                    .id("shuffle-button")
                    
                    // Previous Button (Skip Previous)
                    Button(action: {
                        UIImpactFeedbackGenerator.medium()
                        // If less than 5 seconds in, go to previous song, otherwise restart current song
                        if viewModel.currentTime < 5.0 {
                            viewModel.previous()
                        } else {
                            viewModel.seek(to: 0)
                        }
                    }) {
                        Image(systemName: "backward.end.fill")
                            .font(.title2)
                            .foregroundStyle(Color("AppAccent"))
                    }
                    .disabled(viewModel.currentTrack == nil)
                    .id("previous-button")
                    
                    // Play/Pause Button
                    Button(action: {
                        UIImpactFeedbackGenerator.medium()
                        viewModel.togglePlayPause()
                    }) {
                        Image(systemName: viewModel.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                            .font(.system(size: 64))
                            .foregroundStyle(Color("AppAccent"))
                    }
                    .disabled(viewModel.currentTrack == nil)
                    .id("play-pause-button")
                    
                    // Next Button (Skip Next)
                    Button(action: {
                        UIImpactFeedbackGenerator.medium()
                        viewModel.next()
                    }) {
                        Image(systemName: "forward.end.fill")
                            .font(.title2)
                            .foregroundStyle(Color("AppAccent"))
                    }
                    .disabled(viewModel.currentTrack == nil)
                    .id("next-button")
                    
                    // Repeat Button (right of next)
                    Button(action: {
                        UIImpactFeedbackGenerator.light()
                        viewModel.toggleRepeat()
                    }) {
                        Group {
                            switch viewModel.repeatMode {
                            case .off:
                                Image(systemName: "repeat")
                            case .all:
                                Image(systemName: "repeat")
                            case .one:
                                Image(systemName: "repeat.1")
                            }
                        }
                        .font(.title3)
                        .foregroundStyle(viewModel.repeatMode != .off ? Color("AppAccent") : Color("AppTextPrimary"))
                    }
                    .disabled(viewModel.currentTrack == nil)
                    .id("repeat-button")
                }
                .padding(.vertical)
                .animation(nil, value: viewModel.currentTrack?.id)
                .animation(nil, value: viewModel.isPlaying)
                .animation(nil, value: viewModel.isShuffleEnabled)
                .animation(nil, value: viewModel.repeatMode)
            }
            .padding()
            
            Spacer()
        }
        .sheet(isPresented: $showUpNext) {
            UpNextView(viewModel: viewModel)
        }
        .background(Color("AppSurface"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Done") {
                    UIImpactFeedbackGenerator.light()
                    dismiss()
                }
            }
        }
        // Disable implicit animations for the entire view to prevent unwanted layout shifts
        .transaction { transaction in
            transaction.animation = nil
        }
    }
    
    private func loadAlbumArt() {
        guard let track = viewModel.currentTrack else {
            // Only clear image if there's no track - otherwise keep showing current image
            isLoadingArt = false
            return
        }
        
        // Get image URL - prefer track ID for Emby
        let imageURL: URL? = {
            // Try track ID first (Emby often has images on tracks)
            if let url = viewModel.buildTrackImageURL(trackId: track.id, albumId: track.albumId) {
                Self.logger.debug("loadAlbumArt: Using trackId URL for TrackID: \(track.id), URL: \(url.absoluteString)")
                return url
            }
            // Fallback to album ID
            if let albumId = track.albumId,
               let url = viewModel.albumArtURL(for: albumId) {
                Self.logger.debug("loadAlbumArt: Using albumId URL for TrackID: \(track.id), AlbumID: \(albumId), URL: \(url.absoluteString)")
                return url
            }
            Self.logger.warning("loadAlbumArt: No image URL found for TrackID: \(track.id), AlbumID: \(track.albumId ?? "nil")")
            return nil
        }()
        
        guard let imageURL = imageURL else {
            // No URL available - clear image and stop loading
            isLoadingArt = false
            // Only clear image if we're sure there's no image to show
            Task { @MainActor in
                albumArtImage = nil
            }
            return
        }
        
        isLoadingArt = true
        
        Task {
            // Store the track ID we're loading for to prevent race conditions
            let loadingTrackId = track.id
            
            do {
                var request = URLRequest(url: imageURL)
                request.cachePolicy = .returnCacheDataElseLoad
                request.timeoutInterval = 10.0
                
                let (data, response) = try await URLSession.shared.data(for: request)
                
                // Check if track changed while loading
                let currentTrackId = await MainActor.run {
                    viewModel.currentTrack?.id
                }
                guard currentTrackId == loadingTrackId else {
                    Self.logger.debug("loadAlbumArt: Track changed while loading, discarding image")
                    await MainActor.run {
                        isLoadingArt = false
                    }
                    return
                }
                
                // Check for HTTP errors
                if let httpResponse = response as? HTTPURLResponse {
                    if httpResponse.statusCode != 200 {
                        Self.logger.error("loadAlbumArt: HTTP \(httpResponse.statusCode) for URL: \(imageURL.absoluteString)")
                        await MainActor.run {
                            // Only clear if still loading for this track
                            if viewModel.currentTrack?.id == loadingTrackId {
                                albumArtImage = nil
                                isLoadingArt = false
                            }
                        }
                        return
                    }
                }
                
                // Verify it's actually image data
                guard let uiImage = UIImage(data: data) else {
                    Self.logger.error("loadAlbumArt: Invalid image data for URL: \(imageURL.absoluteString)")
                    await MainActor.run {
                        // Only clear if still loading for this track
                        if viewModel.currentTrack?.id == loadingTrackId {
                            albumArtImage = nil
                            isLoadingArt = false
                        }
                    }
                    return
                }
                
                await MainActor.run {
                    // Only update if still loading for this track
                    if viewModel.currentTrack?.id == loadingTrackId {
                        albumArtImage = uiImage
                        isLoadingArt = false
                        Self.logger.debug("loadAlbumArt: Successfully loaded image from \(imageURL.absoluteString)")
                    } else {
                        Self.logger.debug("loadAlbumArt: Track changed after loading, discarding image")
                    }
                }
            } catch {
                Self.logger.error("loadAlbumArt: Failed to load image from \(imageURL.absoluteString): \(error.localizedDescription)")
                await MainActor.run {
                    // Only clear if still loading for this track
                    if viewModel.currentTrack?.id == loadingTrackId {
                        albumArtImage = nil
                        isLoadingArt = false
                    }
                }
            }
        }
    }
    
    private var albumArtPlaceholder: some View {
        Rectangle()
            .fill(
                LinearGradient(
                    colors: [Color.blue.opacity(0.3), Color.purple.opacity(0.3)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .aspectRatio(1, contentMode: .fit)
            .overlay(
                VStack {
                    Image(systemName: "music.note")
                        .font(.system(size: 80))
                        .foregroundStyle(Color("AppTextPrimary").opacity(0.6))
                }
            )
    }
    
    private func formatTime(_ time: TimeInterval) -> String {
        // Handle invalid time values
        guard time.isFinite && !time.isNaN && time >= 0 else {
            return "0:00"
        }
        
        let totalSeconds = Int(time.rounded())
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

// Custom slider that maintains pill shape and proper drag handling across all iOS versions
struct CustomSlider: UIViewRepresentable {
    @Binding var value: Double
    var range: ClosedRange<Double>
    var onEditingChanged: (Bool) -> Void
    
    init(
        value: Binding<Double>,
        in range: ClosedRange<Double>,
        onEditingChanged: @escaping (Bool) -> Void = { _ in }
    ) {
        self._value = value
        self.range = range
        self.onEditingChanged = onEditingChanged
    }
    
    func makeUIView(context: Context) -> UISlider {
        let slider = UISlider()
        slider.minimumValue = Float(range.lowerBound)
        slider.maximumValue = Float(range.upperBound)
        slider.value = Float(value)
        
        // Set accent color for the track
        let accentColor = UIColor(named: "AppAccent") ?? UIColor.systemYellow
        slider.tintColor = accentColor
        slider.minimumTrackTintColor = accentColor
        slider.maximumTrackTintColor = UIColor.systemGray4
        
        // Set thumb color while preserving pill shape
        // Always use custom thumb image to ensure pill shape and proper appearance
        // Set for all states to prevent any default styling from being applied
        let thumbImage = createPillThumbImage(color: accentColor)
        slider.setThumbImage(thumbImage, for: .normal)
        slider.setThumbImage(thumbImage, for: .highlighted)
        slider.setThumbImage(thumbImage, for: .selected)
        slider.setThumbImage(thumbImage, for: .disabled)
        
        // Explicitly clear thumbTintColor to prevent it from overriding our custom image
        slider.thumbTintColor = nil
        
        // Add tap gesture recognizer for tap-to-seek
        // Allow the gesture to work alongside the slider's native gestures
        let tapGesture = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        tapGesture.cancelsTouchesInView = false
        slider.addGestureRecognizer(tapGesture)
        
        // Add target for value changes
        slider.addTarget(context.coordinator, action: #selector(Coordinator.valueChanged(_:)), for: .valueChanged)
        slider.addTarget(context.coordinator, action: #selector(Coordinator.dragStarted(_:)), for: .touchDown)
        slider.addTarget(context.coordinator, action: #selector(Coordinator.dragEnded(_:)), for: [.touchUpInside, .touchUpOutside])
        
        return slider
    }
    
    // Create a pill-shaped thumb image with the specified color
    // Matches iOS default slider thumb size and appearance (pill shape with transparency/glow)
    private func createPillThumbImage(color: UIColor) -> UIImage {
        let size = CGSize(width: 28, height: 28)
        let scale = UIScreen.main.scale
        UIGraphicsBeginImageContextWithOptions(size, false, scale)
        defer { UIGraphicsEndImageContext() }
        
        guard let context = UIGraphicsGetCurrentContext() else {
            // Return a simple fallback image if context creation fails
            return UIImage()
        }
        
        // Draw a pill-shaped (rounded rectangle) thumb matching iOS default
        // The pill shape is created by using a corner radius equal to half the height
        let rect = CGRect(origin: .zero, size: size)
        let cornerRadius = size.height / 2
        let path = UIBezierPath(roundedRect: rect, cornerRadius: cornerRadius)
        
        // Fill with the accent color - use full opacity for the base
        context.setFillColor(color.cgColor)
        path.fill()
        
        // Add a subtle white highlight on the top portion for the glow/transparent effect
        // This mimics the iOS default slider thumb appearance
        context.saveGState()
        let highlightRect = CGRect(x: 2, y: 2, width: size.width - 4, height: (size.height - 4) / 2.5)
        let highlightCornerRadius = max(0, cornerRadius - 2)
        let highlightPath = UIBezierPath(roundedRect: highlightRect, byRoundingCorners: [.topLeft, .topRight], cornerRadii: CGSize(width: highlightCornerRadius, height: highlightCornerRadius))
        
        context.setBlendMode(.normal)
        context.setFillColor(UIColor.white.withAlphaComponent(0.35).cgColor)
        highlightPath.fill()
        context.restoreGState()
        
        guard let image = UIGraphicsGetImageFromCurrentImageContext() else {
            return UIImage()
        }
        
        // Return image with rendering mode to preserve appearance
        return image.withRenderingMode(.alwaysOriginal)
    }
    
    func updateUIView(_ slider: UISlider, context: Context) {
        // Only update if the change didn't come from user interaction
        if !context.coordinator.isDragging {
            slider.value = Float(value)
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject {
        var parent: CustomSlider
        var isDragging = false
        
        init(_ parent: CustomSlider) {
            self.parent = parent
        }
        
        @objc func valueChanged(_ slider: UISlider) {
            parent.value = Double(slider.value)
        }
        
        @objc func dragStarted(_ slider: UISlider) {
            isDragging = true
            parent.onEditingChanged(true)
        }
        
        @objc func dragEnded(_ slider: UISlider) {
            isDragging = false
            parent.onEditingChanged(false)
        }
        
        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard let slider = gesture.view as? UISlider else { return }
            
            // Don't handle tap if we're currently dragging
            guard !isDragging else { return }
            
            let location = gesture.location(in: slider)
            let trackRect = slider.trackRect(forBounds: slider.bounds)
            
            // Calculate the tap position
            var tapX = location.x
            tapX = max(trackRect.minX, min(trackRect.maxX, tapX))
            
            // Convert tap position to value
            let percentage = (tapX - trackRect.minX) / trackRect.width
            let newValue = slider.minimumValue + Float(percentage) * (slider.maximumValue - slider.minimumValue)
            let clampedValue = max(slider.minimumValue, min(slider.maximumValue, newValue))
            
            // Update slider value - this will trigger valueChanged which updates the binding
            // The binding's set closure will handle the seeking
            slider.setValue(clampedValue, animated: false)
            parent.value = Double(clampedValue)
        }
    }
}

