
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
        // Test if CarPlaySceneDelegate class is accessible
        let carPlayClass: AnyClass? = NSClassFromString("CarPlaySceneDelegate") ?? NSClassFromString("Kartunes.CarPlaySceneDelegate")
        if carPlayClass != nil {
            logger.info("CarPlaySceneDelegate class is accessible")
            NSLog("CarPlay: CarPlaySceneDelegate class is accessible")
        } else {
            logger.warning("CarPlaySceneDelegate class NOT found - check Info.plist configuration")
            NSLog("CarPlay: WARNING - CarPlaySceneDelegate class NOT found!")
        }
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

