
import SwiftUI
import CoreData
import UIKit

struct SettingsView: View {
    @EnvironmentObject var coordinator: AppCoordinator
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.colorScheme) private var systemColorScheme
    @State private var syncError: String?
    @State private var hasInitializedTheme = false
    @State private var showingAddServer = false
    @AppStorage(UserDefaultsKeys.selectedTheme)
    private var selectedThemeRawValue: String = AppTheme.system.rawValue

    private var selectedTheme: AppTheme {
        get { AppTheme(rawValue: selectedThemeRawValue) ?? .system }
        set { selectedThemeRawValue = newValue.rawValue }
    }
    
    private var selectedThemeBinding: Binding<AppTheme> {
        Binding(
            get: { AppTheme(rawValue: selectedThemeRawValue) ?? .system },
            set: { selectedThemeRawValue = $0.rawValue }
        )
    }
    
    private func initializeThemeIfNeeded() {
        guard !hasInitializedTheme else { return }
        hasInitializedTheme = true
        
        // Check if theme has been set before
        let hasStoredTheme = UserDefaults.standard.string(forKey: UserDefaultsKeys.selectedTheme) != nil
        if !hasStoredTheme {
            // Detect system appearance and set default
            let systemAppearance = UITraitCollection.current.userInterfaceStyle
            let defaultTheme: AppTheme
            switch systemAppearance {
            case .dark:
                defaultTheme = .dark
            case .light:
                defaultTheme = .light
            case .unspecified:
                defaultTheme = .dark // Default to dark if undefined
            @unknown default:
                defaultTheme = .dark
            }
            selectedThemeRawValue = defaultTheme.rawValue
        }
    }
    
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(key: "name", ascending: true)],
        animation: .default
    ) private var allServers: FetchedResults<CDServer>
    
    @FetchRequest(
        sortDescriptors: [],
        predicate: NSPredicate(format: "isActive == YES"),
        animation: .default
    ) private var activeServers: FetchedResults<CDServer>
    
    private var activeServer: CDServer? {
        // First try to get from fetch request
        if let server = activeServers.first {
            return server
        }
        // Fallback: find by ID from coordinator
        if let serverId = coordinator.activeServer?.id {
            let request: NSFetchRequest<CDServer> = CDServer.fetchRequest()
            request.predicate = NSPredicate(format: "id == %@", serverId as CVarArg)
            request.fetchLimit = 1
            return try? viewContext.fetch(request).first
        }
        return nil
    }
    
    var body: some View {
        NavigationStack {
            List {
                Section(header: Text("Appearance")) {
                    Picker("Theme", selection: selectedThemeBinding) {
                        ForEach(AppTheme.allCases) { theme in
                            Text(theme.label).tag(theme)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                
                Section("Servers") {
                    Button(action: {
                        UIImpactFeedbackGenerator.medium()
                        showingAddServer = true
                    }) {
                        HStack {
                            Image(systemName: "plus.circle.fill")
                                .foregroundStyle(Color("AppAccent"))
                            Text("Add Server")
                                .foregroundStyle(Color("AppTextPrimary"))
                        }
                    }
                    
                    if allServers.isEmpty {
                        Text("No servers configured")
                            .foregroundStyle(Color("AppTextSecondary"))
                    } else {
                        ForEach(allServers) { server in
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text(server.name ?? "Unknown Server")
                                            .font(.headline)
                                        if server.isActive {
                                            Text("(Active)")
                                                .font(.caption)
                                                .foregroundStyle(Color("AppAccent"))
                                        }
                                        // Server type indicator
                                        if let typeRaw = server.typeRaw,
                                           let serverType = MediaServerType(rawValue: typeRaw) {
                                            Text(serverType.displayName)
                                                .font(.caption2)
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 2)
                                                .background(
                                                    RoundedRectangle(cornerRadius: 4)
                                                        .fill(Color("AppAccent").opacity(0.2))
                                                )
                                                .foregroundStyle(Color("AppAccent"))
                                        }
                                    }
                                    Text(server.baseURL ?? "")
                                        .font(.caption)
                                        .foregroundStyle(Color("AppTextSecondary"))
                                    Text("User: \(server.username ?? "")")
                                        .font(.caption)
                                        .foregroundStyle(Color("AppTextSecondary"))
                                }
                                
                                Spacer()
                                
                                if !server.isActive {
                                    Button(action: {
                                        UIImpactFeedbackGenerator.medium()
                                        Task {
                                            // Get server type from Core Data
                                            let serverType: MediaServerType
                                            if let typeRaw = server.typeRaw, let type = MediaServerType(rawValue: typeRaw) {
                                                serverType = type
                                            } else {
                                                serverType = .jellyfin
                                            }
                                            
                                            let serverDomain = Server(
                                                id: server.id ?? UUID(),
                                                name: server.name ?? "",
                                                baseURL: URL(string: server.baseURL ?? "") ?? URL(string: "https://example.com")!,
                                                username: server.username ?? "",
                                                userId: server.userId ?? "",
                                                accessToken: server.accessToken ?? "",
                                                serverType: serverType
                                            )
                                            await coordinator.authRepository.setActiveServer(serverDomain)
                                            await MainActor.run {
                                                coordinator.activeServer = serverDomain
                                            }
                                        }
                                    }) {
                                        Text("Activate")
                                            .font(.subheadline)
                                            .foregroundStyle(Color("AppAccent"))
                                    }
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
                
                Section("Active Server") {
                    if let server = coordinator.activeServer {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(server.name)
                                    .font(.headline)
                                // Server type indicator
                                Text(server.serverType.displayName)
                                    .font(.caption2)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(
                                        RoundedRectangle(cornerRadius: 4)
                                            .fill(Color("AppAccent").opacity(0.2))
                                    )
                                    .foregroundStyle(Color("AppAccent"))
                            }
                            Text(server.baseURL.absoluteString)
                                .font(.caption)
                                .foregroundStyle(Color("AppTextSecondary"))
                            Text("User: \(server.username)")
                                .font(.caption)
                                .foregroundStyle(Color("AppTextSecondary"))
                        }
                        .padding(.vertical, 4)
                    } else {
                        Text("No server connected")
                            .foregroundStyle(Color("AppTextSecondary"))
                    }
                }
                
                if coordinator.activeServer != nil {
                    Section("Library") {
                        if let server = activeServer, let lastFullSync = server.lastFullSync {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Last full sync:")
                                    .font(.caption)
                                    .foregroundStyle(Color("AppTextSecondary"))
                                Text(lastFullSync, style: .date)
                                    .font(.subheadline)
                                    .foregroundStyle(Color("AppTextPrimary"))
                                Text(lastFullSync, style: .time)
                                    .font(.caption)
                                    .foregroundStyle(Color("AppTextSecondary"))
                            }
                        } else {
                            Text("Last full sync: never")
                                .foregroundStyle(Color("AppTextSecondary"))
                        }
                        
                        if let server = activeServer {
                            VStack(alignment: .leading, spacing: 8) {
                                Button(action: {
                                    UIImpactFeedbackGenerator.medium()
                                    Task {
                                        await performFullSync(server: server)
                                    }
                                }) {
                                    HStack {
                                        if coordinator.isSyncing {
                                            ProgressView()
                                                .progressViewStyle(CircularProgressViewStyle())
                                        }
                                        Text(coordinator.isSyncing ? coordinator.syncStage : "Full Library Scan")
                                    }
                                }
                                .disabled(coordinator.isSyncing)
                                
                                if coordinator.isSyncing {
                                    VStack(alignment: .leading, spacing: 4) {
                                        ProgressView(value: coordinator.syncProgress)
                                            .progressViewStyle(LinearProgressViewStyle())
                                        Text("\(Int(coordinator.syncProgress * 100))%")
                                            .font(.caption)
                                            .foregroundStyle(Color("AppTextSecondary"))
                                    }
                                }
                            }
                        } else {
                            Button(action: {}) {
                                Text("Full Library Scan")
                            }
                            .disabled(true)
                        }
                        
                        if let syncError = syncError {
                            Text(syncError)
                                .font(.caption)
                                .foregroundColor(.red)
                        }
                    }
                }
                
                if coordinator.activeServer != nil {
                    Section("Actions") {
                        Button(role: .destructive, action: {
                            UIImpactFeedbackGenerator.heavy()
                            Task {
                                // Stop playback and clear queue before deleting server
                                await MainActor.run {
                                    coordinator.playbackViewModel.stop()
                                }
                                
                                // Get the ID of the server we're about to delete
                                guard let serverIdToDelete = coordinator.activeServer?.id else {
                                    return
                                }
                                
                                // Delete the active server and all its data
                                await coordinator.authRepository.deleteServer(serverId: serverIdToDelete)
                                
                                // Check if there are other servers available
                                let remainingServers = try? await coordinator.authRepository.listServers()
                                
                                if let otherServers = remainingServers, !otherServers.isEmpty {
                                    // Activate the first available server
                                    let nextServer = otherServers[0]
                                    await coordinator.authRepository.setActiveServer(nextServer)
                                    await MainActor.run {
                                        coordinator.activeServer = nextServer
                                    }
                                    // Server activated - no need to log
                                } else {
                                    // No servers left, clear active server (will show LoginView)
                                    await coordinator.authRepository.deactivateAllServers()
                                    await MainActor.run {
                                        coordinator.activeServer = nil
                                    }
                                    // No servers remaining - no need to log
                                }
                            }
                        }) {
                            Text("Disconnect & Delete Server")
                        }
                        .disabled(coordinator.activeServer == nil)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color("AppBackground"))
            .safeAreaInset(edge: .bottom) {
                Spacer()
                    .frame(height: coordinator.playbackViewModel.currentTrack != nil ? 100 : 0) // Mini player height + padding
            }
            .navigationTitle("Settings")
            .onAppear {
                initializeThemeIfNeeded()
            }
            .sheet(isPresented: $showingAddServer) {
                NavigationStack {
                    LoginView(shouldActivateServer: true) {
                        showingAddServer = false
                    }
                    .environmentObject(coordinator)
                }
            }
        }
    }
    
    private func performFullSync(server: CDServer) async {
        guard let syncManager = coordinator.syncManager else {
            await MainActor.run {
                syncError = "Sync manager not available"
            }
            return
        }
        
        await MainActor.run {
            coordinator.isSyncing = true
            coordinator.syncProgress = 0.0
            coordinator.syncStage = "Starting..."
            syncError = nil
        }
        
        do {
            try await syncManager.performFullSync(for: server) { progress in
                coordinator.syncProgress = progress.progress
                coordinator.syncStage = progress.stage
            }
            await MainActor.run {
                coordinator.isSyncing = false
                coordinator.syncProgress = 1.0
                coordinator.syncStage = "Complete"
                // Refresh the view context to see updated lastFullSync
                viewContext.refresh(server, mergeChanges: true)
            }
        } catch {
            await MainActor.run {
                coordinator.isSyncing = false
                coordinator.syncProgress = 0.0
                coordinator.syncStage = ""
                syncError = "Sync failed: \(error.localizedDescription)"
            }
        }
    }
}

