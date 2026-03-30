import SwiftUI

// MARK: - WindowCoordinator

/// Quản lý singleton cửa sổ ConnectionsListView (ẩn/hiện).
@MainActor
final class WindowCoordinator: ObservableObject {
    static let shared = WindowCoordinator()
    private init() {}

    /// Ẩn cửa sổ Connections (khi vừa connect)
    func hideConnectionsWindow() {
        connectionsWindow?.orderOut(nil)
    }

    /// Hiện lại cửa sổ Connections (khi database window đóng)
    func showConnectionsWindow() {
        if let win = connectionsWindow {
            win.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private var connectionsWindow: NSWindow? {
        NSApp.windows.first { $0.title == "Connections" }
    }
}

// MARK: - App

@main
struct MongoDesktopApp: App {
    @StateObject private var connectionStore = ConnectionStore()

    var body: some Scene {
        // Main window: Connections list (singleton)
        WindowGroup("Connections") {
            ConnectionsListView()
                .environmentObject(connectionStore)
                .environmentObject(GlobalSettings.shared)
        }
        .defaultSize(width: 720, height: 500)

        // Database windows: one per connection (opened via openWindow(value:))
        WindowGroup("Database", for: ConnectionProfile.ID.self) { $connectionId in
            DatabaseWindowView(connectionId: connectionId)
                .environmentObject(connectionStore)
                .environmentObject(GlobalSettings.shared)
        }
        .defaultSize(width: 1000, height: 720)
        .restorationBehavior(.disabled)
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unified(showsTitle: true))

        Settings {
            SettingsView()
                .environmentObject(GlobalSettings.shared)
        }

        .commands {
            CommandGroup(replacing: .appSettings) {
                SettingsLink {
                    Text("Settings…")
                }
            }
        }
    }
}
