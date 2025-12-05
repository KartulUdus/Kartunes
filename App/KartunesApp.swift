
import SwiftUI
import CoreData
import UIKit

@main
struct KartunesApp: App {
    @StateObject private var appCoordinator = AppCoordinator()
    @AppStorage(UserDefaultsKeys.selectedTheme)
    private var selectedThemeRawValue: String = AppTheme.system.rawValue
    
    private let logger = Log.make(.appCoordinator)

    private var selectedTheme: AppTheme {
        AppTheme(rawValue: selectedThemeRawValue) ?? .system
    }
    
    init() {
        logger.info("App initializing")
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if appCoordinator.activeServer == nil {
                    LoginView()
                        .environmentObject(appCoordinator)
                } else {
                    RootView()
                        .environmentObject(appCoordinator)
                }
            }
            .preferredColorScheme(selectedTheme.colorSchemeOverride)
            .environment(\.managedObjectContext, CoreDataStack.shared.viewContext)
            .task {
                await appCoordinator.loadActiveServer()
            }
        }
    }
}

