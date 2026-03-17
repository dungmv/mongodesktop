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

    func testConnection(uri: String) async throws {
        let elg = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        let client = try MongoClient(uri, using: elg)
        do {
            _ = try await client.db("admin").runCommand(["ping": 1])
            try await closeTemporaryClient(client, elg)
        } catch {
            try? await closeTemporaryClient(client, elg)
            throw error
        }
    }

    func disconnect() async throws {
        // Close the Mongo client in a non-blocking way
        if let client {
            // Offload potential blocking close to a detached task
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                Task.detached {
                    do {
                        try client.syncClose()
                        continuation.resume()
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
            self.client = nil
        }

        // Shut down the EventLoopGroup without blocking the async context
        if let eventLoopGroup {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                eventLoopGroup.shutdownGracefully { error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume()
                    }
                }
            }
            self.eventLoopGroup = nil
        }

        connectedURI = nil
    }

    private func closeTemporaryClient(_ client: MongoClient, _ eventLoopGroup: MultiThreadedEventLoopGroup) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            Task.detached {
                do {
                    try client.syncClose()
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            eventLoopGroup.shutdownGracefully { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
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

    func serverVersion() async throws -> String {
        guard let client else { throw MongoServiceError.notConnected }
        let result = try await client.db("admin").runCommand(["buildInfo": 1])
        if case let .string(version) = result["version"] {
            return version
        }
        return "unknown"
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
