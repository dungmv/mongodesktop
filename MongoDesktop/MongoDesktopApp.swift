import SwiftUI

@main
struct MongoDesktopApp: App {
    @StateObject private var connectionStore = ConnectionStore()
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup("Connections") {
            ConnectionsListView()
                .environmentObject(connectionStore)
                .environmentObject(appState)
        }

        WindowGroup("Mongo Desktop", id: "main") {
            ConnectionsView()
                .environmentObject(connectionStore)
                .environmentObject(appState)
        }
    }
}
