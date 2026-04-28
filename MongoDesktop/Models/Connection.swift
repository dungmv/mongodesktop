import Foundation

// MARK: - SSH Tunnel Config

struct SSHTunnelConfig: Codable, Hashable {
    var sshHost: String
    var sshPort: Int
    var sshUser: String
    /// Authentication mode
    var authMode: SSHAuthMode
    /// Password (used when authMode == .password)
    var password: String
    /// Path to private key file (used when authMode == .privateKey)
    var privateKeyPath: String
    /// Passphrase for the private key (optional)
    var privateKeyPassphrase: String

    enum SSHAuthMode: String, Codable, CaseIterable, Hashable {
        case password    = "Password"
        case privateKey  = "Private Key"
    }

    init(
        sshHost: String = "",
        sshPort: Int = 22,
        sshUser: String = "",
        authMode: SSHAuthMode = .password,
        password: String = "",
        privateKeyPath: String = "",
        privateKeyPassphrase: String = ""
    ) {
        self.sshHost = sshHost
        self.sshPort = sshPort
        self.sshUser = sshUser
        self.authMode = authMode
        self.password = password
        self.privateKeyPath = privateKeyPath
        self.privateKeyPassphrase = privateKeyPassphrase
    }
}

// MARK: - ConnectionProfile

struct ConnectionProfile: Identifiable, Codable, Hashable {
    var id: UUID
    var name: String
    var host: String
    var port: Int
    var username: String
    var password: String
    var database: String
    var authDatabase: String
    var useSRV: Bool
    var useSSL: Bool
    var createdAt: Date
    var lastConnectedAt: Date?

    // SSH Tunnel
    var useSSHTunnel: Bool
    var sshTunnel: SSHTunnelConfig

    init(
        id: UUID = UUID(),
        name: String,
        host: String,
        port: Int = 27017,
        username: String = "",
        password: String = "",
        database: String = "",
        authDatabase: String = "",
        useSRV: Bool = false,
        useSSL: Bool = false,
        createdAt: Date = Date(),
        lastConnectedAt: Date? = nil,
        useSSHTunnel: Bool = false,
        sshTunnel: SSHTunnelConfig = SSHTunnelConfig()
    ) {
        self.id = id
        self.name = name
        self.host = host
        self.port = port
        self.username = username
        self.password = password
        self.database = database
        self.authDatabase = authDatabase
        self.useSRV = useSRV
        self.useSSL = useSSL
        self.createdAt = createdAt
        self.lastConnectedAt = lastConnectedAt
        self.useSSHTunnel = useSSHTunnel
        self.sshTunnel = sshTunnel
    }

    var connectionString: String {
        return buildURI(maskPassword: false)
    }

    var displayConnectionString: String {
        return buildURI(maskPassword: true)
    }

    private func buildURI(maskPassword: Bool) -> String {
        let scheme = useSRV ? "mongodb+srv" : "mongodb"
        var uri = "\(scheme)://"

        if !username.isEmpty {
            let user = ConnectionProfile.percentEncode(username)
            uri += user
            if !password.isEmpty {
                if maskPassword {
                    uri += ":***"
                } else {
                    let pass = ConnectionProfile.percentEncode(password)
                    uri += ":\(pass)"
                }
            }
            uri += "@"
        }

        uri += host

        if !useSRV && port != 27017 {
            uri += ":\(port)"
        }

        if !database.isEmpty {
            uri += "/\(database)"
        }

        var queryItems: [String] = []

        if !authDatabase.isEmpty {
            queryItems.append("authSource=\(authDatabase)")
        }

        if useSSL {
            queryItems.append("tls=true")
        }

        if !queryItems.isEmpty {
            uri += "?" + queryItems.joined(separator: "&")
        }

        return uri
    }

    private static func percentEncode(_ value: String) -> String {
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }
}

// MARK: - ConnectionStore

@MainActor
final class ConnectionStore: ObservableObject {
    @Published private(set) var connections: [ConnectionProfile] = []

    private let fileURL: URL

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let folder = appSupport.appendingPathComponent("MongoDesktop", isDirectory: true)
        self.fileURL = folder.appendingPathComponent("connections.json")
        load()
    }

    func load() {
        do {
            let data = try Data(contentsOf: fileURL)
            connections = try JSONDecoder().decode([ConnectionProfile].self, from: data)
        } catch {
            connections = []
        }
    }

    func add(_ connection: ConnectionProfile) {
        connections.append(connection)
        save()
    }

    func update(_ connection: ConnectionProfile) {
        guard let index = connections.firstIndex(where: { $0.id == connection.id }) else { return }
        connections[index] = connection
        save()
    }

    func delete(_ connection: ConnectionProfile) {
        connections.removeAll { $0.id == connection.id }
        save()
    }

    func markConnected(_ connectionId: UUID) {
        guard let index = connections.firstIndex(where: { $0.id == connectionId }) else { return }
        connections[index].lastConnectedAt = Date()
        save()
    }

    private func save() {
        do {
            let folder = fileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(connections)
            try data.write(to: fileURL, options: [.atomic])
        } catch {
            // Silent fail; in-memory changes remain visible.
        }
    }
}
