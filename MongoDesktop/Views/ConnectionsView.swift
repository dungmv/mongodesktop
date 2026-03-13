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
    @Published var serverVersion: String = ""
    @Published var lastQueryDuration: TimeInterval? = nil  // seconds

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
                // Fetch server version in parallel with databases
                async let versionFetch: () = fetchServerVersion()
                await refreshDatabases()
                await versionFetch
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
            serverVersion = ""
            lastQueryDuration = nil
        }
    }

    func fetchServerVersion() async {
        do {
            let version = try await MongoService.shared.serverVersion()
            await MainActor.run { serverVersion = version }
        } catch {
            // Non-critical – ignore
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
        await MainActor.run { isLoading = true; lastError = nil; lastQueryDuration = nil }
        let start = Date()
        do {
            let filter = try parseFilter(filterText)
            let skip = currentPage * pageSize
            let docs = try await MongoService.shared.findDocuments(
                database: database, collection: collection,
                filter: filter, limit: pageSize, skip: skip
            )
            let elapsed = Date().timeIntervalSince(start)
            await MainActor.run {
                documents = docs
                hasMore = docs.count == pageSize
                selectedRowIds = []
                lastQueryDuration = elapsed
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
            // Group 1 (navigation): connection name, database picker, refresh
            ToolbarItemGroup(placement: .navigation) {
                HStack(spacing: 4) {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 7, height: 7)
                    Text(appState.connectionName)
                        .font(.headline)
                        .foregroundStyle(.primary)
                }

                Divider()
                    .frame(height: 16)
                    .padding(.horizontal, 2)

                DatabasePickerButton()
                    .environmentObject(appState)

                Button(action: { Task { await appState.refreshDatabases() } }) {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Refresh databases")
            }

            // Group 2 (trailing): server info + loading/query time
            ToolbarItemGroup(placement: .primaryAction) {
                QueryStatusView()
                    .environmentObject(appState)
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

// MARK: - DatabasePickerButton

struct DatabasePickerButton: View {
    @EnvironmentObject private var appState: AppState
    @State private var isPresented = false
    @State private var searchText = ""

    private var filtered: [String] {
        searchText.isEmpty
            ? appState.databases
            : appState.databases.filter { $0.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        Button(action: { isPresented.toggle() }) {
            HStack(spacing: 5) {
                Image(systemName: "cylinder.split.1x2")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                Text(appState.selectedDatabase ?? "Chọn database")
                    .font(.system(.body, design: .rounded, weight: .medium))
                    .foregroundStyle(appState.selectedDatabase == nil ? .secondary : .primary)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            DatabasePickerPopover(
                databases: filtered,
                selected: appState.selectedDatabase,
                searchText: $searchText,
                onSelect: { db in
                    isPresented = false
                    appState.selectedDatabase = db
                    Task { await appState.refreshCollections(database: db) }
                }
            )
        }
    }
}

// MARK: - DatabasePickerPopover

struct DatabasePickerPopover: View {
    let databases: [String]
    let selected: String?
    @Binding var searchText: String
    let onSelect: (String) -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Search field
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .font(.callout)
                TextField("Tìm database...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.callout)
                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            Divider()

            if databases.isEmpty {
                Text(searchText.isEmpty ? "Không có database" : "Không tìm thấy")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(20)
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(databases, id: \.self) { db in
                            DatabasePickerRow(
                                name: db,
                                isSelected: selected == db,
                                onTap: { onSelect(db) }
                            )
                        }
                    }
                    .padding(6)
                }
                .frame(maxHeight: 260)
            }
        }
        .frame(minWidth: 220)
        .background(.regularMaterial)
    }
}

// MARK: - DatabasePickerRow

struct DatabasePickerRow: View {
    let name: String
    let isSelected: Bool
    let onTap: () -> Void
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "cylinder.split.1x2")
                .font(.caption)
                .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                .frame(width: 16)
            Text(name)
                .font(.system(.body, design: .rounded))
                .foregroundStyle(.primary)
            Spacer()
            if isSelected {
                Image(systemName: "checkmark")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(isSelected
                      ? Color.accentColor.opacity(0.12)
                      : (isHovered ? Color.primary.opacity(0.06) : Color.clear))
        )
        .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .onTapGesture { onTap() }
        .onHover { isHovered = $0 }
    }
}

// MARK: - QueryStatusView

struct QueryStatusView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        HStack(spacing: 8) {
            if appState.isLoading {
                ProgressView()
                    .scaleEffect(0.75)
                    .transition(.opacity)
            } else if let duration = appState.lastQueryDuration {
                HStack(spacing: 4) {
                    Image(systemName: "clock")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(formattedDuration(duration))
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                .transition(.opacity)
            }

            if !appState.serverVersion.isEmpty {
                Divider()
                    .frame(height: 14)
                    .opacity(appState.isLoading || appState.lastQueryDuration != nil ? 1 : 0)

                HStack(spacing: 4) {
                    Image(systemName: "leaf.fill")
                        .font(.caption)
                        .foregroundStyle(.green.opacity(0.8))
                    Text("mongo \(appState.serverVersion)")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .animation(.easeInOut(duration: 0.2), value: appState.isLoading)
        .animation(.easeInOut(duration: 0.2), value: appState.lastQueryDuration)
    }

    private func formattedDuration(_ seconds: TimeInterval) -> String {
        if seconds < 1 {
            return "\(Int(seconds * 1000))ms"
        } else {
            return String(format: "%.2fs", seconds)
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
