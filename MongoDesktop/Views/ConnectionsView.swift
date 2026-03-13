import SwiftUI
import MongoSwift

// MARK: - AppState (per-window, not shared globally)

@MainActor
final class AppState: ObservableObject {
    @Published var selectedConnectionId: ConnectionProfile.ID?
    @Published var isConnected: Bool = false
    @Published var statusMessage: String = "Chưa kết nối"
    @Published var databases: [String] = []
    @Published var collections: [String] = []
    @Published var documents: [BSONDocument] = []
    @Published var selectedDatabase: String?
    @Published var selectedCollection: String?
    @Published var filterText: String = "{}"
    @Published var viewMode: DocumentViewMode = .table
    @Published var pageSize: Int = 100
    @Published var currentPage: Int = 0
    @Published var hasMore: Bool = false
    @Published var selectedRowIds: Set<String> = []
    @Published var isLoading: Bool = false
    @Published var lastError: String?
    @Published var connectionName: String = ""

    func connect(using connection: ConnectionProfile, store: ConnectionStore) {
        isLoading = true
        lastError = nil
        statusMessage = "Đang kết nối..."
        connectionName = connection.name
        selectedConnectionId = connection.id

        Task {
            do {
                try await MongoService.shared.connect(uri: connection.connectionString)
                await MainActor.run {
                    isConnected = true
                    statusMessage = "Đã kết nối: \(connection.name)"
                    store.markConnected(connection.id)
                }
                await refreshDatabases()
            } catch {
                await MainActor.run {
                    isConnected = false
                    statusMessage = "Kết nối thất bại"
                    lastError = error.localizedDescription
                }
            }
            await MainActor.run { isLoading = false }
        }
    }

    func disconnect() async throws {
        try await MongoService.shared.disconnect()
        await MainActor.run {
            isConnected = false
            statusMessage = "Đã ngắt kết nối"
            databases = []
            collections = []
            documents = []
            selectedDatabase = nil
            selectedCollection = nil
        }
    }

    func refreshDatabases() async {
        await MainActor.run { isLoading = true; lastError = nil }
        do {
            let list = try await MongoService.shared.listDatabases()
            await MainActor.run {
                databases = list
                if selectedDatabase == nil { selectedDatabase = list.first }
            }
        } catch {
            await MainActor.run { lastError = error.localizedDescription }
        }
        await MainActor.run { isLoading = false }
        if let db = selectedDatabase { await refreshCollections(database: db) }
    }

    func refreshCollections(database: String) async {
        await MainActor.run { isLoading = true; lastError = nil }
        do {
            let list = try await MongoService.shared.listCollections(database: database)
            await MainActor.run {
                collections = list
                if selectedCollection == nil { selectedCollection = list.first }
                currentPage = 0
            }
        } catch {
            await MainActor.run { lastError = error.localizedDescription }
        }
        await MainActor.run { isLoading = false }
        if let col = selectedCollection { await runFind(database: database, collection: col) }
    }

    func runFind(database: String, collection: String) async {
        await MainActor.run { isLoading = true; lastError = nil }
        do {
            let filter = try parseFilter(filterText)
            let skip = currentPage * pageSize
            let docs = try await MongoService.shared.findDocuments(
                database: database, collection: collection,
                filter: filter, limit: pageSize, skip: skip
            )
            await MainActor.run {
                documents = docs
                hasMore = docs.count == pageSize
                selectedRowIds = []
            }
        } catch {
            await MainActor.run { lastError = error.localizedDescription }
        }
        await MainActor.run { isLoading = false }
    }

    func parseFilter(_ text: String) throws -> BSONDocument {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed == "{}" { return BSONDocument() }
        return try BSONDocument(fromJSON: trimmed)
    }

    func nextPage() async {
        guard hasMore else { return }
        currentPage += 1
        if let db = selectedDatabase, let col = selectedCollection {
            await runFind(database: db, collection: col)
        }
    }

    func previousPage() async {
        guard currentPage > 0 else { return }
        currentPage -= 1
        if let db = selectedDatabase, let col = selectedCollection {
            await runFind(database: db, collection: col)
        }
    }
}

// MARK: - DocumentViewMode

enum DocumentViewMode: String, CaseIterable, Identifiable {
    case table = "Table"
    case json = "JSON"
    var id: String { rawValue }
}

// MARK: - DatabaseWindowView
// Each window gets its OWN @StateObject AppState – fully independent

struct DatabaseWindowView: View {
    let connectionId: ConnectionProfile.ID?

    @EnvironmentObject private var connectionStore: ConnectionStore
    @StateObject private var windowState = AppState()

    var body: some View {
        Group {
            if windowState.isConnected {
                DatabaseBrowserView()
                    .environmentObject(windowState)
                    .environmentObject(connectionStore)
            } else if windowState.isLoading {
                connectingView
            } else {
                failedView
            }
        }
        .onAppear { connectOnAppear() }
        .frame(minWidth: 900, minHeight: 600)
    }

    private var connectingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.2)
            Text("Đang kết nối…")
                .font(.headline)
                .foregroundStyle(.secondary)
            if let connection = resolvedConnection {
                Text(connection.connectionString)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .padding(.horizontal, 40)
            }
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
            if let error = windowState.lastError {
                Text(error)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
            Button("Thử lại") { connectOnAppear() }
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var resolvedConnection: ConnectionProfile? {
        guard let id = connectionId else { return nil }
        return connectionStore.connections.first { $0.id == id }
    }

    private func connectOnAppear() {
        guard let connection = resolvedConnection else { return }
        windowState.connect(using: connection, store: connectionStore)
    }
}

// MARK: - DatabaseBrowserView

struct DatabaseBrowserView: View {
    @EnvironmentObject private var connectionStore: ConnectionStore
    @EnvironmentObject private var appState: AppState

    var body: some View {
        NavigationSplitView {
            CollectionSidebarView()
                .environmentObject(appState)
        } detail: {
            DatabaseDetailView()
                .environmentObject(appState)
        }
        .navigationSplitViewStyle(.balanced)
        .navigationTitle(appState.connectionName)
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 8, height: 8)
                    Text(appState.connectionName)
                        .font(.headline)
                        .foregroundStyle(.primary)
                }
            }

            ToolbarItemGroup(placement: .primaryAction) {
                if appState.isLoading {
                    ProgressView().scaleEffect(0.8)
                }

                Picker("Database", selection: $appState.selectedDatabase) {
                    ForEach(appState.databases, id: \.self) { db in
                        Text(db).tag(Optional(db))
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 180)
                .onChange(of: appState.selectedDatabase) { _, newValue in
                    guard let newValue else { return }
                    Task { await appState.refreshCollections(database: newValue) }
                }

                Button(action: { Task { await appState.refreshDatabases() } }) {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .help("Refresh databases")
            }
        }
        .toolbarBackground(.visible, for: .windowToolbar)
        .toolbarBackground(.ultraThinMaterial, for: .windowToolbar)
        .overlay(alignment: .topLeading) {
            if let error = appState.lastError {
                ErrorBannerView(message: error) { appState.lastError = nil }
                    .padding(12)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .animation(.spring(duration: 0.4), value: appState.lastError)
            }
        }
    }
}

// MARK: - CollectionSidebarView

struct CollectionSidebarView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Image(systemName: "folder.fill")
                    .foregroundStyle(.secondary)
                Text("Collections")
                    .font(.headline)
                Spacer()
                Text("\(appState.collections.count)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.quaternary, in: Capsule())
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            Divider().padding(.horizontal, 8)

            if appState.collections.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "tray")
                        .font(.largeTitle)
                        .foregroundStyle(.tertiary)
                    Text("Không có collection")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(appState.collections, id: \.self, selection: $appState.selectedCollection) { col in
                    Label(col, systemImage: "tablecells")
                        .font(.system(.body, design: .rounded))
                }
                .listStyle(.sidebar)
                .scrollContentBackground(.hidden)
                .onChange(of: appState.selectedCollection) { _, newValue in
                    guard let newValue, let db = appState.selectedDatabase else { return }
                    appState.currentPage = 0
                    Task { await appState.runFind(database: db, collection: newValue) }
                }
            }
        }
        .background(.regularMaterial)
    }
}

// MARK: - ErrorBannerView

struct ErrorBannerView: View {
    let message: String
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(message)
                .font(.callout)
                .lineLimit(2)
            Spacer()
            Button(action: onDismiss) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.orange.opacity(0.4), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.12), radius: 8, y: 4)
    }
}
