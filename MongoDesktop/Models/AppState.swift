import SwiftUI

// MARK: - AppState (per-window, not shared globally)

@MainActor
final class AppState: ObservableObject {
    @Published var selectedConnectionId: ConnectionProfile.ID?
    @Published var isConnected: Bool = false
    @Published var statusMessage: String = "Chưa kết nối"
    @Published var databases: [String] = []
    @Published var collections: [String] = []
    @Published var timeSeriesCollections: Set<String> = []
    @Published var selectedDatabase: String?
    @Published var selectedCollection: String?
    @Published var isLoading: Bool = false
    @Published var lastError: String?
    @Published var connectionName: String = ""
    @Published var serverVersion: String = ""

    func connect(using connection: ConnectionProfile, store: ConnectionStore) {
        Task { @MainActor in
            isLoading = true
            lastError = nil
            statusMessage = "Đang kết nối..."
            connectionName = connection.name
            selectedConnectionId = connection.id
            if !connection.database.isEmpty {
                selectedDatabase = connection.database
            } else {
                selectedDatabase = nil
            }
            selectedCollection = nil
            
            do {
                try await MongoService.shared.connect(uri: connection.connectionString)
                isConnected = true
                statusMessage = "Đã kết nối: \(connection.name)"
                store.markConnected(connection.id)
                async let versionFetch: () = fetchServerVersion()
                await refreshDatabases()
                await versionFetch
            } catch {
                isConnected = false
                statusMessage = "Kết nối thất bại"
                lastError = error.localizedDescription
            }
            isLoading = false
        }
    }

    func disconnect() async throws {
        try await MongoService.shared.disconnect()
        isConnected = false
        statusMessage = "Đã ngắt kết nối"
        databases = []
        collections = []
        timeSeriesCollections = []
        selectedDatabase = nil
        selectedCollection = nil
        serverVersion = ""
    }

    func fetchServerVersion() async {
        do {
            let version = try await MongoService.shared.serverVersion()
            serverVersion = version
        } catch {
            // Non-critical
        }
    }

    func refreshDatabases() async {
        isLoading = true
        lastError = nil
        do {
            let list = try await MongoService.shared.listDatabases()
            databases = list
            if let selected = selectedDatabase, !list.contains(selected) {
                selectedDatabase = nil
            }
            if selectedDatabase == nil { selectedDatabase = list.first }
        } catch {
            lastError = error.localizedDescription
        }
        isLoading = false
        if let db = selectedDatabase { await refreshCollections(database: db) }
    }

    func refreshCollections(database: String) async {
        isLoading = true
        lastError = nil
        do {
            let infos = try await MongoService.shared.listCollectionInfos(database: database)
            let list = infos.map(\.name)
            let timeSeries = Set(infos.filter(\.isTimeSeries).map(\.name))
            collections = list
            timeSeriesCollections = timeSeries
        } catch {
            lastError = error.localizedDescription
        }
        isLoading = false
    }
}

// MARK: - DocumentViewMode

enum DocumentViewMode: String, CaseIterable, Identifiable {
    case table = "Table"
    case json = "JSON"
    var id: String { rawValue }
}
