//
//  kartunesApp.swift
//  kartunes
//
//  Created by Derek on 01.12.2025.
//

import SwiftUI
import CoreData

@main
struct kartunesApp: App {
    let persistenceController = PersistenceController.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
        }
    }
}
