import Foundation
import SwiftUI

@MainActor
final class DatabaseSessionViewModel: ObservableObject {
    @Published var selectedConnectionId: ConnectionProfile.ID?
    @Published var isConnected = false
    @Published var statusMessage = "Not connected"
    @Published var databases: [String] = []
    @Published var collections: [String] = []
    @Published var timeSeriesCollections: Set<String> = []
    @Published var selectedDatabase: String?
    @Published var selectedCollection: String?
    @Published var isLoading = false
    @Published var lastError: String?
    @Published var connectionName = ""
    @Published var serverVersion = ""

    private let mongoService: MongoService

    init(mongoService: MongoService = .shared) {
        self.mongoService = mongoService
    }

    func connect(using connection: ConnectionProfile, store: ConnectionStore) {
        Task { @MainActor in
            isLoading = true
            lastError = nil
            statusMessage = "Connecting..."
            connectionName = connection.name
            selectedConnectionId = connection.id
            selectedDatabase = connection.database.isEmpty ? nil : connection.database
            selectedCollection = nil

            do {
                let uri: String
                if connection.useSSHTunnel {
                    statusMessage = "Setting up SSH SOCKS5 proxy…"
                    #if DEBUG
                    print("[SSH] Starting SOCKS5 proxy → \(connection.sshTunnel.sshUser)@\(connection.sshTunnel.sshHost):\(connection.sshTunnel.sshPort)")
                    #endif
                    let localPort = try await SSHTunnelService.shared.startSOCKS5Proxy(config: connection.sshTunnel)
                    uri = connection.tunnelConnectionString(localPort: localPort)
                    #if DEBUG
                    print("[SSH] SOCKS5 proxy ready on port \(localPort)")
                    print("[SSH] MongoDB URI: \(uri)")
                    #endif
                } else {
                    uri = connection.connectionString
                }

                try await mongoService.connect(uri: uri)
                isConnected = true
                statusMessage = "Connected: \(connection.name)"
                store.markConnected(connection.id)
                async let versionFetch: Void = fetchServerVersion()
                await refreshDatabases()
                await versionFetch
            } catch {
                isConnected = false
                statusMessage = "Connection failed"
                lastError = error.localizedDescription
                if connection.useSSHTunnel {
                    await SSHTunnelService.shared.stopTunnel()
                }
            }

            isLoading = false
        }
    }

    func disconnect() async throws {
        try await mongoService.disconnect()
        await SSHTunnelService.shared.stopTunnel()
        resetConnectionState(statusMessage: "Disconnected")
    }

    func fetchServerVersion() async {
        do {
            serverVersion = try await mongoService.serverVersion()
        } catch {
            // Non-critical metadata.
        }
    }

    func refreshDatabases() async {
        isLoading = true
        lastError = nil

        do {
            let list = try await mongoService.listDatabases()
            databases = list
            if let selectedDatabase, !list.contains(selectedDatabase) {
                self.selectedDatabase = nil
            }
            if selectedDatabase == nil {
                selectedDatabase = list.first
            }
        } catch {
            lastError = error.localizedDescription
        }

        isLoading = false
        if let selectedDatabase {
            await refreshCollections(database: selectedDatabase)
        }
    }

    func refreshCollections(database: String) async {
        isLoading = true
        lastError = nil

        do {
            let infos = try await mongoService.listCollectionInfos(database: database)
            collections = infos.map(\.name)
            timeSeriesCollections = Set(infos.filter(\.isTimeSeries).map(\.name))
        } catch {
            lastError = error.localizedDescription
        }

        isLoading = false
    }

    func selectDatabase(_ database: String) {
        selectedDatabase = database
        selectedCollection = nil
        Task { await refreshCollections(database: database) }
    }

    func selectCollection(database: String?, collection: String?) {
        if let database {
            selectedDatabase = database
        }
        selectedCollection = collection
    }

    func clearError() {
        lastError = nil
    }

    private func resetConnectionState(statusMessage: String) {
        isConnected = false
        self.statusMessage = statusMessage
        databases = []
        collections = []
        timeSeriesCollections = []
        selectedDatabase = nil
        selectedCollection = nil
        serverVersion = ""
    }
}
