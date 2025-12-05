
import SwiftUI
import Combine

struct RootView: View {
    private static let logger = Log.make(.appCoordinator)
    
    @EnvironmentObject var coordinator: AppCoordinator
    @Environment(\.horizontalSizeClass) private var originalSizeClass
    @State private var selectedTab: Int = 0
    
    var body: some View {
        ZStack(alignment: .bottom) {
            classicBottomTabView
            // Mini Player - pill above tab bar
            // Use @ObservedObject wrapper to ensure we observe changes to playbackViewModel
            MiniPlayerContainer(playbackViewModel: coordinator.playbackViewModel)
            
            // Toast message overlay
            if let toast = coordinator.toastMessage {
                ToastView(toast: toast, onDismiss: {
                    coordinator.toastMessage = nil
                }, onAction: {
                    // Navigate to Settings tab
                    selectedTab = 3
                    coordinator.toastMessage = nil
                })
                .transition(.move(edge: .top).combined(with: .opacity))
                .zIndex(1000)
            }
        }
        .onChange(of: coordinator.playbackViewModel.currentTrack) { oldValue, newValue in
            Self.logger.debug("currentTrack changed from \(oldValue?.title ?? "nil") to \(newValue?.title ?? "nil")")
        }
    }
    
    private var classicBottomTabView: some View {
        TabView(selection: $selectedTab) {
            HomeView()
                // restore the *real* size class to the tab content
                .environment(\.horizontalSizeClass, originalSizeClass)
                .tabItem {
                    Label("Home", systemImage: "house.fill")
                }
                .tag(0)

            LibraryView()
                .environment(\.horizontalSizeClass, originalSizeClass)
                .tabItem {
                    Label("Library", systemImage: "music.note.list")
                }
                .tag(1)

            SearchView()
                .environment(\.horizontalSizeClass, originalSizeClass)
                .tabItem {
                    Label("Search", systemImage: "magnifyingglass")
                }
                .tag(2)

            SettingsView()
                .environment(\.horizontalSizeClass, originalSizeClass)
                .tabItem {
                    Label("Settings", systemImage: "gearshape")
                }
                .tag(3)
        }
        // 👇 Force "iPhone-style" compact tab bar layout
        .environment(\.horizontalSizeClass, .compact)
        .toolbarBackground(Color("AppSurface"), for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
        .tint(Color("AppAccent")) // Set tab bar selection color to accent
    }
}

// Separate view to properly observe PlaybackViewModel
private struct MiniPlayerContainer: View {
    @ObservedObject var playbackViewModel: PlaybackViewModel
    
    var body: some View {
        if playbackViewModel.currentTrack != nil {
            VStack(spacing: 0) {
                MiniPlayerView(viewModel: playbackViewModel)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 60) // Position above tab bar (tab bar height ~49 + padding)
            }
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: playbackViewModel.currentTrack != nil)
        }
    }
}

// MARK: - Toast View

struct ToastView: View {
    let toast: ToastMessage
    let onDismiss: () -> Void
    let onAction: () -> Void
    @State private var isVisible = false
    
    var body: some View {
        VStack {
            HStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(toast.message)
                        .font(.subheadline)
                        .foregroundStyle(Color("AppTextPrimary"))
                    
                    if let actionText = toast.actionText {
                        Button(action: onAction) {
                            Text(actionText)
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundStyle(Color("AppAccent"))
                        }
                    }
                }
                
                Spacer()
                
                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Color("AppTextSecondary"))
                }
            }
            .padding(16)
            .background(Color("AppCardBackground"))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .shadow(color: Color.black.opacity(0.2), radius: 8, x: 0, y: 4)
            .padding(.horizontal, 16)
            .padding(.top, 8)
            
            Spacer()
        }
        .opacity(isVisible ? 1 : 0)
        .offset(y: isVisible ? 0 : -100)
        .onAppear {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                isVisible = true
            }
            
            // Auto-dismiss after 5 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                withAnimation {
                    isVisible = false
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    onDismiss()
                }
            }
        }
    }
}
