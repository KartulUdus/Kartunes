
import SwiftUI
import Foundation
import CoreData
import UIKit

struct LoginView: View {
    @EnvironmentObject var coordinator: AppCoordinator
    @State private var serverURL = ""
    @State private var username = ""
    @State private var password = ""
    @State private var friendlyName = ""
    @State private var detectedServerType: MediaServerType?
    @State private var detectedServerName: String?
    @State private var isDetecting = false
    @State private var isConnecting = false
    @State private var errorMessage: String?
    
    private static let logger = Log.make(.auth)
    
    // If false, server will be added but not set as active (for adding secondary servers)
    var shouldActivateServer: Bool = true
    var onSuccess: (() -> Void)? = nil
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Server Configuration")) {
                    TextField("Server URL (e.g., localhost:8096)", text: $serverURL)
                        .textContentType(.URL)
                        .autocapitalization(.none)
                        .autocorrectionDisabled()
                        .onChange(of: serverURL) { oldValue, newValue in
                            // Clear detection when URL changes
                            detectedServerType = nil
                            detectedServerName = nil
                        }
                    
                    if isDetecting {
                        HStack {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle())
                            Text("Detecting server type...")
                                .font(.caption)
                                .foregroundStyle(Color("AppTextSecondary"))
                        }
                    } else if let detectedType = detectedServerType {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(Color("AppAccent"))
                            Text("Detected: \(detectedType.displayName)")
                                .font(.subheadline)
                                .foregroundStyle(Color("AppTextPrimary"))
                        }
                        if let serverName = detectedServerName {
                            Text("Server: \(serverName)")
                                .font(.caption)
                                .foregroundStyle(Color("AppTextSecondary"))
                        }
                    }
                    
                    TextField("Friendly Name (optional)", text: $friendlyName)
                        .textContentType(.name)
                }
                
                Section(header: Text("Credentials")) {
                    TextField("Username", text: $username)
                        .textContentType(.username)
                        .autocapitalization(.none)
                        .autocorrectionDisabled()
                    
                    SecureField("Password", text: $password)
                        .textContentType(.password)
                }
                
                if let errorMessage = errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundColor(.red)
                            .font(.caption)
                    }
                }
                
                Section {
                    Button(action: {
                        UIImpactFeedbackGenerator.medium()
                        connect()
                    }) {
                        HStack {
                            if isConnecting {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle())
                            }
                            Text(isConnecting ? "Connecting..." : "Connect")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .disabled(isConnecting || serverURL.isEmpty || username.isEmpty || password.isEmpty)
                }
            }
            .navigationTitle("Connect to Server")
        }
    }
    
    private func connect() {
        let urlString = serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard !urlString.isEmpty else {
            errorMessage = "Please enter a server URL"
            return
        }
        
        isConnecting = true
        isDetecting = true
        errorMessage = nil
        detectedServerType = nil
        detectedServerName = nil
        
        Task {
            // Determine which URLs to try
            let urlsToTry: [URL]
            if urlString.contains("://") {
                // User provided a protocol, use it as-is
                guard let url = URL(string: urlString) else {
                    await MainActor.run {
                        errorMessage = "Invalid server URL"
                        isConnecting = false
                        isDetecting = false
                    }
                    return
                }
                urlsToTry = [url]
            } else {
                // No protocol provided - determine order based on host
                let isLocalhost = urlString.lowercased().contains("localhost") || 
                                 urlString.contains("127.0.0.1") ||
                                 urlString.contains("::1")
                
                guard let httpURL = URL(string: "http://\(urlString)"),
                      let httpsURL = URL(string: "https://\(urlString)") else {
                    await MainActor.run {
                        errorMessage = "Invalid server URL"
                        isConnecting = false
                        isDetecting = false
                    }
                    return
                }
                
                // For localhost, try HTTP first (most local servers don't have SSL)
                // For remote servers, try HTTPS first (more secure, common for production)
                if isLocalhost {
                    urlsToTry = [httpURL, httpsURL]
                } else {
                    urlsToTry = [httpsURL, httpURL]
                }
            }
            
            // Detect server type by trying each URL
            var detectedResult: ServerDetectionResult?
            
            // First, detect server type
            for url in urlsToTry {
                do {
                    Self.logger.debug("Detecting server type at \(url.absoluteString)")
                    let detection = try await ServerDetectionService.detectServerType(from: url)
                    detectedResult = detection
                    
                    await MainActor.run {
                        detectedServerType = detection.serverType
                        detectedServerName = detection.serverName
                        isDetecting = false
                    }
                    
                    Self.logger.info("Detected \(detection.serverType.displayName) server at \(detection.baseURL.absoluteString)")
                    break // Successfully detected, use this URL
                } catch {
                    Self.logger.warning("Detection failed for \(url.absoluteString): \(error.localizedDescription)")
                    // Continue to next URL
                }
            }
            
            // If detection failed, try fallback authentication with both server types
            var finalBaseURL: URL?
            var detectedType: MediaServerType?
            
            if let detection = detectedResult {
                // Detection succeeded
                finalBaseURL = detection.baseURL
                detectedType = detection.serverType
            } else {
                // Detection failed - try to determine from URL and attempt authentication with both types
                await MainActor.run {
                    isDetecting = false
                }
                
                // Use the first URL that worked (or first one if none worked)
                let urlToTry = urlsToTry.first ?? URL(string: "http://\(serverURL)")!
                
                // Always try Emby first in fallback, since Jellyfin auth might work on Emby
                // but then fail on subsequent API calls (missing /emby prefix)
                // If Emby fails, we'll try Jellyfin
                let serverTypesToTry: [MediaServerType] = [.emby, .jellyfin]
                
                // Normalize URL - we'll let each server type's resolveFinalURL handle it
                // Just use the URL as-is for now
                let normalizedURL = urlToTry
                
                // Try authentication with each server type
                var lastError: Error?
                for serverType in serverTypesToTry {
                    do {
                        Self.logger.debug("Trying authentication as \(serverType.displayName) server")
                        
                        // Adjust URL based on server type
                        var authURL = normalizedURL
                        if serverType == .emby {
                            // Ensure /emby is in path for Emby
                            var components = URLComponents(url: normalizedURL, resolvingAgainstBaseURL: false)!
                            if !components.path.lowercased().contains("/emby") {
                                components.path = "/emby"
                            }
                            if let url = components.url {
                                authURL = url
                            }
                        } else {
                            // For Jellyfin, ensure no /emby in path
                            var components = URLComponents(url: normalizedURL, resolvingAgainstBaseURL: false)!
                            if components.path.lowercased().contains("/emby") {
                                components.path = ""
                            }
                            if let url = components.url {
                                authURL = url
                            }
                        }
                        
                        let tempClient = MediaServerAPIClientFactory.createClient(
                            serverType: serverType,
                            baseURL: authURL
                        )
                        let tempAuthRepo = MediaServerAuthRepository(apiClient: tempClient)
                        
                        // Try to authenticate and add server (this will fail if wrong server type)
                        let server = try await tempAuthRepo.addServer(
                            host: authURL,
                            username: username,
                            password: password,
                            friendlyName: friendlyName.isEmpty ? (authURL.host ?? "\(serverType.displayName) Server") : friendlyName,
                            serverType: serverType
                        )
                        
                        // Verify the server type by trying a simple API call
                        // This catches cases where Jellyfin auth works on Emby but API calls fail
                        if serverType == .jellyfin {
                            // Try a simple API call to verify it's actually Jellyfin
                            // If this fails, it might be Emby
                            do {
                                _ = try await tempClient.fetchMusicLibraries()
                                Self.logger.info("Verified \(serverType.displayName) server (API call succeeded)")
                            } catch {
                                // API call failed - might be wrong server type
                                Self.logger.warning("Authentication succeeded but API call failed for \(serverType.displayName), might be wrong server type")
                                // Continue to next server type
                                lastError = error
                                continue
                            }
                        }
                        
                        // If we get here, authentication and verification succeeded!
                        finalBaseURL = authURL
                        detectedType = serverType
                        Self.logger.info("Successfully authenticated as \(serverType.displayName) server")
                        
                        // Activate server if needed
                        if shouldActivateServer {
                            await coordinator.authRepository.setActiveServer(server)
                            
                            await MainActor.run {
                                coordinator.activeServer = server
                            }
                            
                            try? await Task.sleep(nanoseconds: 200_000_000)
                            await triggerInitialSync(for: server)
                        }
                        
                        // Call success callback if provided
                        await MainActor.run {
                            onSuccess?()
                            isConnecting = false
                            isDetecting = false
                        }
                        return // Success - exit early
                    } catch {
                        Self.logger.warning("Authentication failed as \(serverType.displayName): \(error.localizedDescription)")
                        lastError = error
                        // Continue to next server type
                    }
                }
                
                // If both attempts failed, show error
                guard finalBaseURL != nil, detectedType != nil else {
                    await MainActor.run {
                        isConnecting = false
                        if let lastErr = lastError {
                            let nsError = lastErr as NSError
                            if nsError.code == 401 {
                                errorMessage = "Authentication failed. Please check your username and password."
                            } else {
                                errorMessage = "Could not connect to server. Please check the server URL and ensure it's a Jellyfin or Emby server."
                            }
                        } else {
                            errorMessage = "Could not connect to server. Please check the server URL and ensure it's a Jellyfin or Emby server."
                        }
                    }
                    return
                }
            }
            
            // Now authenticate with the detected server type (only if detection succeeded)
            // If we're here and finalBaseURL/detectedType are set, it means detection succeeded
            // If detection failed, we would have already handled it in the fallback path above
            guard let baseURL = finalBaseURL, let type = detectedType else {
                await MainActor.run {
                    isConnecting = false
                    errorMessage = "Could not determine server type. Please check the server URL."
                }
                return
            }
            
            do {
                Self.logger.debug("Attempting authentication to \(baseURL.absoluteString)")
                
                // Create temporary API client for authentication with detected type
                let tempClient = MediaServerAPIClientFactory.createClient(
                    serverType: type,
                    baseURL: baseURL
                )
                let tempAuthRepo = MediaServerAuthRepository(apiClient: tempClient)
                
                let defaultName = type == .jellyfin ? "Jellyfin Server" : "Emby Server"
                let server = try await tempAuthRepo.addServer(
                    host: baseURL,
                    username: username,
                    password: password,
                    friendlyName: friendlyName.isEmpty ? (detectedResult?.serverName ?? baseURL.host ?? defaultName) : friendlyName,
                    serverType: type
                )
                
                if shouldActivateServer {
                    await coordinator.authRepository.setActiveServer(server)
                    
                    // Update coordinator with new server (this will recreate repositories)
                    await MainActor.run {
                        coordinator.activeServer = server
                    }
                    
                    // Wait a moment for coordinator to update repositories and create sync manager
                    try? await Task.sleep(nanoseconds: 200_000_000) // 0.2 seconds
                    
                    // Trigger initial full sync for new server
                    await triggerInitialSync(for: server)
                } else {
                    // Just add the server without activating it
                    // Server is already saved to Core Data by addServer
                }
                
                // Call success callback if provided
                await MainActor.run {
                    onSuccess?()
                }
                
                await MainActor.run {
                    isConnecting = false
                    isDetecting = false
                }
                return // Success!
            } catch {
                Self.logger.error("Failed to authenticate to \(baseURL.absoluteString): \(error.localizedDescription)")
                
                // Authentication failed - show error
                await MainActor.run {
                    let nsError = error as NSError
                    if nsError.code == 401 {
                        errorMessage = "Authentication failed. Please check your username and password."
                    } else {
                        errorMessage = "Failed to authenticate: \(error.localizedDescription)"
                    }
                    isConnecting = false
                    isDetecting = false
                }
            }
        }
    }
    
    private func triggerInitialSync(for server: Server) async {
        // Get the CDServer from Core Data
        let context = CoreDataStack.shared.viewContext
        guard let cdServer = try? await context.perform({
            let request: NSFetchRequest<CDServer> = CDServer.fetchRequest()
            request.predicate = NSPredicate(format: "id == %@", server.id as CVarArg)
            request.fetchLimit = 1
            return try context.fetch(request).first
        }) else {
            Self.logger.warning("Could not find server in Core Data for sync")
            return
        }
        
        // Wait a bit for coordinator to update repositories after setting active server
        try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
        
        // Use coordinator's sync manager to ensure state is updated
        // Access coordinator on main actor since it's an @EnvironmentObject
        let syncManager = await MainActor.run {
            return coordinator.syncManager
        }
        
        guard let syncManager = syncManager else {
            Self.logger.warning("Sync manager not available yet, will sync on next app load")
            return
        }
        
        Self.logger.info("Triggering initial full sync for new server")
        
        // Update coordinator sync state
        await MainActor.run {
            coordinator.isSyncing = true
            coordinator.syncProgress = 0.0
            coordinator.syncStage = "Starting..."
        }
        
        do {
            try await syncManager.performFullSync(for: cdServer) { progress in
                Task { @MainActor in
                    coordinator.syncProgress = progress.progress
                    coordinator.syncStage = progress.stage
                }
            }
            
            await MainActor.run {
                coordinator.isSyncing = false
                coordinator.syncProgress = 1.0
                coordinator.syncStage = "Complete"
            }
            Self.logger.info("Initial full sync completed successfully")
        } catch {
            await MainActor.run {
                coordinator.isSyncing = false
                coordinator.syncProgress = 0.0
                coordinator.syncStage = ""
            }
            Self.logger.error("Initial full sync failed: \(error.localizedDescription)")
            // Don't show error to user - they can manually sync from settings
        }
    }
}

