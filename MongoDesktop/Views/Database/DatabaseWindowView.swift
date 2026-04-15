import SwiftUI

// MARK: - DatabaseWindowView

struct DatabaseWindowView: View {
    let connectionId: ConnectionProfile.ID?

    @EnvironmentObject private var connectionStore: ConnectionStore
    @StateObject private var appState = AppState()
    @State private var tabs: [DatabaseTab] = []
    @State private var selectedTabId: DatabaseTab.ID?

    var body: some View {
        Group {
            if let connection = resolvedConnection {
                if let selectedTab {
                    DatabaseTabContentView(
                        connection: connection,
                        connectionStore: connectionStore,
                        appState: appState,
                        tabState: selectedTab.state
                    )
                    .environment(\.addDatabaseTab, addTab)
                    .environment(\.databaseTabContext, tabContext)
                } else {
                    loadingTabView
                }
            } else {
                missingConnectionView
            }
        }
        .onAppear { ensureInitialTab() }
        .onAppear { connectIfNeeded() }
        .onDisappear {
            Task { try? await MongoService.shared.disconnect() }
            // Hiện lại cửa sổ Connections khi Database window đóng
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                WindowCoordinator.shared.showConnectionsWindow()
            }
        }
        .frame(minWidth: 900, idealWidth: 1000, minHeight: 600, idealHeight: 720)
    }

    private var missingConnectionView: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(.secondary)
            Text("Không tìm thấy connection")
                .font(.title2.weight(.semibold))
            Text("Vui lòng mở lại từ danh sách Connections.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var resolvedConnection: ConnectionProfile? {
        guard let id = connectionId else { return nil }
        return connectionStore.connections.first { $0.id == id }
    }

    private func ensureInitialTab() {
        guard tabs.isEmpty else { return }
        DispatchQueue.main.async {
            self.addTab()
        }
    }

    private func addTab() {
        let state = QueryTabState()
        if let db = appState.selectedDatabase, let col = appState.selectedCollection, !col.isEmpty {
            state.title = col
            state.databaseName = db
            state.collectionName = col
        } else if let db = appState.selectedDatabase, !db.isEmpty {
            state.title = db
            state.databaseName = db
        }
        let tab = DatabaseTab(id: UUID(), state: state)
        tabs.append(tab)
        selectedTabId = tab.id
        if state.collectionName != nil {
            state.isLoading = true
            state.documents = []
            Task { await state.runFind(appState: appState) }
        }
    }

    private func openTab(database: String, collection: String) {
        // 1. If a tab for this collection already exists, just switch to it
        if let existingTab = tabs.first(where: { $0.state.databaseName == database && $0.state.collectionName == collection }) {
            selectedTabId = existingTab.id
            appState.selectedDatabase = database
            appState.selectedCollection = collection
            return
        }

        // 2. Otherwise, check if current tab is completely empty, and reuse it
        if let currentTabId = selectedTabId,
           let index = tabs.firstIndex(where: { $0.id == currentTabId }),
           tabs[index].state.collectionName == nil {
            
            let state = tabs[index].state
            state.title = collection
            state.databaseName = database
            state.collectionName = collection
            appState.selectedDatabase = database
            appState.selectedCollection = collection
            state.isLoading = true
            state.documents = []
            Task { await state.runFind(appState: appState) }
            
        } else {
            let state = QueryTabState()
            state.title = collection
            state.databaseName = database
            state.collectionName = collection
            state.isLoading = true
            state.documents = []
            let tab = DatabaseTab(id: UUID(), state: state)
            tabs.append(tab)
            selectedTabId = tab.id
            appState.selectedDatabase = database
            appState.selectedCollection = collection
            Task { await state.runFind(appState: appState) }
        }
    }

    private func closeTab(_ id: UUID) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        tabs.remove(at: index)

        if tabs.isEmpty {
            addTab()
            return
        }

        if selectedTabId == id {
            let newIndex = min(index, tabs.count - 1)
            selectedTabId = tabs[newIndex].id
        }
    }

    private var selectedTab: DatabaseTab? {
        guard let selectedTabId else { return nil }
        return tabs.first { $0.id == selectedTabId }
    }

    private var tabContext: DatabaseTabContext {
        let items = tabs.enumerated().map { index, tab in
            DatabaseTabItem(id: tab.id, title: tabTitle(for: tab.state, fallbackIndex: index + 1))
        }
        return DatabaseTabContext(
            tabs: items,
            selectedId: selectedTabId,
            select: { id in
                selectedTabId = id
                if let tab = tabs.first(where: { $0.id == id }) {
                    // Cập nhật lại AppState selection để UI sidebar đồng bộ (nếu muốn)
                    if let db = tab.state.databaseName {
                        appState.selectedDatabase = db
                    }
                    if let col = tab.state.collectionName {
                        appState.selectedCollection = col
                    }
                }
            },
            close: closeTab,
            add: addTab,
            open: openTab
        )
    }

    private func tabTitle(for state: QueryTabState, fallbackIndex: Int) -> String {
        if !state.title.isEmpty { return state.title }
        if let col = state.collectionName, !col.isEmpty { return col }
        if let db = state.databaseName, !db.isEmpty { return db }
        return "Tab \(fallbackIndex)"
    }

    private func connectIfNeeded() {
        guard let connection = resolvedConnection else { return }
        guard !appState.isConnected, !appState.isLoading else { return }
        appState.connect(using: connection, store: connectionStore)
    }

    private var loadingTabView: some View {
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.large)
            Text("Đang chuẩn bị tab…")
                .font(.headline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct DatabaseTab: Identifiable {
    let id: UUID
    let state: QueryTabState
}

private struct DatabaseTabContentView: View {
    let connection: ConnectionProfile
    let connectionStore: ConnectionStore
    @ObservedObject var appState: AppState
    @ObservedObject var tabState: QueryTabState

    var body: some View {
        Group {
            if appState.isConnected {
                DatabaseBrowserView()
                    .environmentObject(appState)
                    .environmentObject(tabState)
                    .environmentObject(connectionStore)
            } else if appState.isLoading {
                connectingView
            } else {
                failedView
            }
        }
        .onAppear { connectIfNeeded() }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func connectIfNeeded() {
        guard !appState.isConnected, !appState.isLoading else { return }
        appState.connect(using: connection, store: connectionStore)
    }

    private var connectingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .controlSize(.large)
                .frame(width: 20, height: 20)
                .fixedSize()
            Text("Đang kết nối…")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text(connection.connectionString)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .truncationMode(.middle)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var failedView: some View {
        VStack(spacing: 16) {
            Image(systemName: "network.slash")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(.secondary)
            Text("Không thể kết nối")
                .font(.title2.weight(.semibold))
            if let error = appState.lastError {
                Text(error)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
            Button("Thử lại") { appState.connect(using: connection, store: connectionStore) }
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
