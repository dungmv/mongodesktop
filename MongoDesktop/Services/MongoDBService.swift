import Foundation
import MongoSwift
import NIOPosix

class MongoDBService {
    static let shared = MongoDBService()
    private var client: MongoClient?
    private var currentConnectionString: String?

    private init() {}

    // MARK: - Connection Management

    func connect(using connection: Connection) async throws -> Bool {
        let uri = connection.connectionString
        return try await connect(usingURI: uri)
    }

    func connect(usingURI uri: String) async throws -> Bool {
        if currentConnectionString == uri, client != nil {
            return true // Already connected
        }
        let elg = MultiThreadedEventLoopGroup(numberOfThreads: 4)

        client = try MongoClient(uri, using: elg)
        currentConnectionString = uri
        // Optionally, ping the server to verify connection
        let adminDb = client!.db("admin")
        _ = try await adminDb.runCommand(["ping": 1])
        return true
    }

    // MARK: - Database Operations

    func listDatabases(for connection: Connection) async throws -> [String] {
        try await connect(using: connection)
        guard let client = client else { throw NSError(domain: "MongoDBService", code: 1, userInfo: [NSLocalizedDescriptionKey: "Not connected"]) }
        let databases = try await client.listDatabases()
        return databases.map { $0.name }
    }

    func listCollections(in database: String, for connection: Connection) async throws -> [String] {
        try await connect(using: connection)
        guard let client = client else { throw NSError(domain: "MongoDBService", code: 1, userInfo: [NSLocalizedDescriptionKey: "Not connected"]) }
        let db = client.db(database)
        let collectionsCursor = try await db.listCollections()
        let collections = try await collectionsCursor.toArray()
        return collections.map { $0.name }
    }

    func countDocuments(in collection: String, database: String, for connection: Connection) async throws -> Int {
        try await connect(using: connection)
        guard let client = client else { throw NSError(domain: "MongoDBService", code: 1, userInfo: [NSLocalizedDescriptionKey: "Not connected"]) }
        let db = client.db(database)
        let coll = db.collection(collection)
        return try await coll.countDocuments()
    }

    func findDocuments(in collection: String, database: String, for connection: Connection, limit: Int = 20, skip: Int = 0) async throws -> [BSONDocument] {
        try await connect(using: connection)
        guard let client = client else { throw NSError(domain: "MongoDBService", code: 1, userInfo: [NSLocalizedDescriptionKey: "Not connected"]) }
        let db = client.db(database)
        let coll = db.collection(collection)
        let options = FindOptions(limit: limit, skip: skip)
        let cursor = try await coll.find(options: options)
        var results: [BSONDocument] = []
        for try await doc in cursor {
            results.append(doc)
        }
        return results
    }
}
