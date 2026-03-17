import SwiftUI
import SwiftBSON

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
    @Published var lastQueryDuration: TimeInterval? = nil

    deinit {
        // Ensure the Mongo client is closed if the window/app is torn down.
        Task {
            try? await MongoService.shared.disconnect()
        }
    }

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
            // Non-critical
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
