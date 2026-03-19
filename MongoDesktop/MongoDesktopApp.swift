import SwiftUI

@main
struct MongoDesktopApp: App {
    @StateObject private var connectionStore = ConnectionStore()

    var body: some Scene {
        // Main window: Connections list
        WindowGroup("Connections") {
            ConnectionsListView()
                .environmentObject(connectionStore)
        }
        .defaultSize(width: 720, height: 500)

        // Database windows: one per connection (opened via openWindow(value:))
        WindowGroup("Database", for: ConnectionProfile.ID.self) { $connectionId in
            DatabaseWindowView(connectionId: connectionId)
                .environmentObject(connectionStore)
        }
        .restorationBehavior(.disabled)
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unified(showsTitle: true))
    }
}
