import Foundation
import MongoSwift
import NIOPosix

actor MongoService {
    static let shared = MongoService()

    private var client: MongoClient?
    private var eventLoopGroup: MultiThreadedEventLoopGroup?
    private var connectedURI: String?

    func connect(uri: String) async throws {
        if connectedURI == uri, client != nil {
            return
        }

        try await disconnect()

        let elg = MultiThreadedEventLoopGroup(numberOfThreads: 2)
        let client = try MongoClient(uri, using: elg)
        let adminDb = client.db("admin")
        _ = try await adminDb.runCommand(["ping": 1])

        self.client = client
        self.eventLoopGroup = elg
        self.connectedURI = uri
    }

    func disconnect() async throws {
        if let client {
            try? client.syncClose()
            self.client = nil
        }

        if let eventLoopGroup {
            try? eventLoopGroup.syncShutdownGracefully()
            self.eventLoopGroup = nil
        }

        connectedURI = nil
    }

    func listDatabases() async throws -> [String] {
        guard let client else { throw MongoServiceError.notConnected }
        let databases = try await client.listDatabases()
        return databases.map { $0.name }.sorted()
    }

    func listCollections(database: String) async throws -> [String] {
        guard let client else { throw MongoServiceError.notConnected }
        let db = client.db(database)
        let cursor = try await db.listCollections()
        let collections = try await cursor.toArray()
        return collections.map { $0.name }.sorted()
    }

    func findDocuments(database: String, collection: String, filter: BSONDocument, limit: Int = 100, skip: Int = 0) async throws -> [BSONDocument] {
        guard let client else { throw MongoServiceError.notConnected }
        let db = client.db(database)
        let coll = db.collection(collection)
        let options = FindOptions(limit: limit, skip: skip)
        let cursor = try await coll.find(filter, options: options)
        var documents: [BSONDocument] = []
        for try await doc in cursor {
            documents.append(doc)
        }
        return documents
    }
}

enum MongoServiceError: LocalizedError {
    case notConnected

    var errorDescription: String? {
        switch self {
        case .notConnected:
            return "Chưa kết nối MongoDB."
        }
    }
}
