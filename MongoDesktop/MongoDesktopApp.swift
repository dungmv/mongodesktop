//
//  MongoDesktopApp.swift
//  MongoDesktop
//
//  Created by Mai Dũng on 29/4/25.
//

import SwiftUI
import SwiftData

@main
struct MongoDesktopApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Connection.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ConnectionsView()
        }
        .modelContainer(sharedModelContainer)
    }
}
