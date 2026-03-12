import SwiftUI
import MongoSwift

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
    @Published var isRightSidebarVisible: Bool = true
    @Published var isLoading: Bool = false
    @Published var lastError: String?

    func connect(using connection: ConnectionProfile, store: ConnectionStore) {
        isLoading = true
        lastError = nil
        statusMessage = "Đang kết nối..."

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

            await MainActor.run {
                isLoading = false
            }
        }
    }

    func disconnect() {
        isLoading = true
        lastError = nil
        statusMessage = "Đang ngắt kết nối..."

        Task {
            do {
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
            } catch {
                await MainActor.run {
                    lastError = error.localizedDescription
                }
            }

            await MainActor.run {
                isLoading = false
            }
        }
    }

    func refreshDatabases() async {
        await MainActor.run {
            isLoading = true
            lastError = nil
        }

        do {
            let list = try await MongoService.shared.listDatabases()
            await MainActor.run {
                databases = list
                if selectedDatabase == nil {
                    selectedDatabase = list.first
                }
            }
        } catch {
            await MainActor.run {
                lastError = error.localizedDescription
            }
        }

        await MainActor.run {
            isLoading = false
        }

        if let selectedDatabase {
            await refreshCollections(database: selectedDatabase)
        }
    }

    func refreshCollections(database: String) async {
        await MainActor.run {
            isLoading = true
            lastError = nil
        }

        do {
            let list = try await MongoService.shared.listCollections(database: database)
            await MainActor.run {
                collections = list
                if selectedCollection == nil {
                    selectedCollection = list.first
                }
                currentPage = 0
            }
        } catch {
            await MainActor.run {
                lastError = error.localizedDescription
            }
        }

        await MainActor.run {
            isLoading = false
        }

        if let selectedCollection {
            await runFind(database: database, collection: selectedCollection)
        }
    }

    func runFind(database: String, collection: String) async {
        await MainActor.run {
            isLoading = true
            lastError = nil
        }

        do {
            let filter = try parseFilter(filterText)
            let skip = currentPage * pageSize
            let docs = try await MongoService.shared.findDocuments(database: database, collection: collection, filter: filter, limit: pageSize, skip: skip)
            await MainActor.run {
                documents = docs
                hasMore = docs.count == pageSize
                selectedRowIds = []
            }
        } catch {
            await MainActor.run {
                lastError = error.localizedDescription
            }
        }

        await MainActor.run {
            isLoading = false
        }
    }

    func parseFilter(_ text: String) throws -> BSONDocument {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed == "{}" {
            return BSONDocument()
        }
        return try BSONDocument(fromJSON: trimmed)
    }

    func nextPage() async {
        guard hasMore else { return }
        currentPage += 1
        if let db = selectedDatabase, let collection = selectedCollection {
            await runFind(database: db, collection: collection)
        }
    }

    func previousPage() async {
        guard currentPage > 0 else { return }
        currentPage -= 1
        if let db = selectedDatabase, let collection = selectedCollection {
            await runFind(database: db, collection: collection)
        }
    }
}

enum DocumentViewMode: String, CaseIterable, Identifiable {
    case table = "Table"
    case json = "JSON"

    var id: String { rawValue }
}

struct ConnectionsView: View {
    @EnvironmentObject private var connectionStore: ConnectionStore
    @EnvironmentObject private var appState: AppState
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color.black.opacity(0.08), Color.blue.opacity(0.12), Color.clear],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            content
                .frame(minWidth: 1000, minHeight: 700)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .padding(12)
        }
    }

    private var content: some View {
        NavigationSplitView {
            CollectionListView()
        } content: {
            Group {
                if appState.isConnected {
                    DatabaseDetailView()
                } else {
                    VStack(spacing: 12) {
                        Text("Hãy chọn connection và kết nối từ cửa sổ Connections.")
                            .foregroundColor(.secondary)
                        Button("Mở Connections") {
                            openWindow(id: "connections")
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        } detail: {
            if appState.viewMode == .table && appState.isRightSidebarVisible {
                RightSidebarView()
            } else {
                EmptyView()
            }
        }
        .navigationSplitViewStyle(.balanced)
        .onChange(of: appState.viewMode) { _, newValue in
            if newValue == .json {
                appState.isRightSidebarVisible = false
            } else if newValue == .table && appState.isRightSidebarVisible == false {
                appState.isRightSidebarVisible = true
            }
        }
        .overlay(alignment: .topLeading) {
            if let error = appState.lastError {
                Text(error)
                    .foregroundColor(.red)
                    .padding(12)
                    .background(.ultraThinMaterial)
                    .cornerRadius(8)
                    .padding(12)
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                Button("Connections") {
                    openWindow(id: "connections")
                }
                .help("Quản lý và kết nối")
            }

            ToolbarItemGroup(placement: .primaryAction) {
                if let connection = currentConnection {
                    Label(connection.name, systemImage: "bolt.horizontal.circle")
                        .foregroundColor(.secondary)
                }

                if appState.isConnected {
                    Button("Ngắt kết nối") {
                        appState.disconnect()
                    }
                }

                Button(appState.isRightSidebarVisible ? "Hide Details" : "Show Details") {
                    appState.isRightSidebarVisible.toggle()
                }
                .disabled(appState.viewMode == .json)

                Picker("Database", selection: $appState.selectedDatabase) {
                    ForEach(appState.databases, id: \.self) { db in
                        Text(db).tag(Optional(db))
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 200)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .onChange(of: appState.selectedDatabase) { _, newValue in
                    guard let newValue else { return }
                    Task { await appState.refreshCollections(database: newValue) }
                }

                Button("Refresh DB") {
                    Task { await appState.refreshDatabases() }
                }

                if appState.isLoading {
                    ProgressView()
                }
            }
        }
        .toolbarBackground(.visible, for: .windowToolbar)
        .toolbarBackground(.ultraThinMaterial, for: .windowToolbar)
    }

    private var currentConnection: ConnectionProfile? {
        guard let id = appState.selectedConnectionId else { return nil }
        return connectionStore.connections.first { $0.id == id }
    }
}

struct RightSidebarView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                GroupBox {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Document")
                            .font(.headline)

                        if let documentText = selectedDocumentText {
                            Text(documentText)
                                .font(.system(.body, design: .monospaced))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                        } else {
                            Text("Chọn một document trong bảng để xem chi tiết.")
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .padding(16)
        }
        .frame(minWidth: 260)
        .background(.regularMaterial)
    }

    private var selectedDocumentText: String? {
        guard let selectedId = appState.selectedRowIds.first else { return nil }
        let rows = appState.documents.enumerated().map { index, doc in
            DocumentRow(document: doc, fallbackIndex: index)
        }
        guard let row = rows.first(where: { $0.id == selectedId }) else { return nil }
        return String(describing: row.document)
    }
}

struct CollectionListView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Collections")
                .font(.headline)
                .padding(12)

            List(appState.collections, id: \.self, selection: $appState.selectedCollection) { collection in
                Text(collection)
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            .background(.regularMaterial)
            .onChange(of: appState.selectedCollection) { _, newValue in
                guard let newValue, let db = appState.selectedDatabase else { return }
                appState.currentPage = 0
                Task { await appState.runFind(database: db, collection: newValue) }
            }
        }
    }
}
