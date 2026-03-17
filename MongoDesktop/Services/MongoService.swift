import Foundation
import SwiftBSON

actor MongoService {
    static let shared = MongoService()

    private var client: OpaquePointer?
    private var connectedURI: String?

    private static let initialized: Void = {
        mongoc_init()
    }()

    private func ensureInitialized() {
        _ = MongoService.initialized
    }

    func connect(uri: String) async throws {
        if connectedURI == uri, client != nil {
            return
        }

        try await disconnect()
        ensureInitialized()

        guard let newClient = mongoc_client_new(uri) else {
            throw MongoServiceError.connectionFailed("Không thể khởi tạo Mongo client.")
        }

        do {
            try ping(client: newClient)
        } catch {
            mongoc_client_destroy(newClient)
            throw error
        }

        self.client = newClient
        self.connectedURI = uri
    }

    func testConnection(uri: String) async throws {
        ensureInitialized()
        guard let tempClient = mongoc_client_new(uri) else {
            throw MongoServiceError.connectionFailed("Không thể khởi tạo Mongo client.")
        }
        defer { mongoc_client_destroy(tempClient) }
        try ping(client: tempClient)
    }

    func debugDNS(uri: String) async -> String {
        await DNSDebugService.debug(uri: uri)
    }

    func disconnect() async throws {
        if let client {
            mongoc_client_destroy(client)
            self.client = nil
        }
        connectedURI = nil
    }

    func listDatabases() async throws -> [String] {
        let client = try requireClient()
        var error = bson_error_t()
        guard let names = mongoc_client_get_database_names_with_opts(client, nil, &error) else {
            throw MongoServiceError.commandFailed(errorMessage(error))
        }
        defer { bson_strfreev(names) }

        var results: [String] = []
        var index = 0
        while let namePtr = names.advanced(by: index).pointee {
            results.append(String(cString: namePtr))
            index += 1
        }

        return results.sorted()
    }

    func listCollections(database: String) async throws -> [String] {
        let client = try requireClient()
        guard let db = mongoc_client_get_database(client, database) else {
            throw MongoServiceError.commandFailed("Không thể mở database '\(database)'.")
        }
        defer { mongoc_database_destroy(db) }

        var error = bson_error_t()
        guard let names = mongoc_database_get_collection_names_with_opts(db, nil, &error) else {
            throw MongoServiceError.commandFailed(errorMessage(error))
        }
        defer { bson_strfreev(names) }

        var results: [String] = []
        var index = 0
        while let namePtr = names.advanced(by: index).pointee {
            results.append(String(cString: namePtr))
            index += 1
        }

        return results.sorted()
    }

    func serverVersion() async throws -> String {
        let client = try requireClient()
        let reply = try runCommand(client: client, database: "admin", command: ["buildInfo": .int32(1)])
        if case let .string(version) = reply["version"] {
            return version
        }
        return "unknown"
    }

    func findDocuments(database: String, collection: String, filter: BSONDocument, limit: Int = 100, skip: Int = 0) async throws -> [BSONDocument] {
        let client = try requireClient()
        guard let db = mongoc_client_get_database(client, database) else {
            throw MongoServiceError.commandFailed("Không thể mở database '\(database)'.")
        }
        defer { mongoc_database_destroy(db) }

        guard let coll = mongoc_database_get_collection(db, collection) else {
            throw MongoServiceError.commandFailed("Không thể mở collection '\(collection)'.")
        }
        defer { mongoc_collection_destroy(coll) }

        let filterJSON = filter.toCanonicalExtendedJSONString()
        let filterBson = try bsonFromJSON(filterJSON)
        defer { bson_destroy(filterBson) }

        var opts = bson_t()
        bson_init(&opts)
        bson_append_int64(&opts, "limit", -1, Int64(limit))
        bson_append_int64(&opts, "skip", -1, Int64(skip))
        defer { bson_destroy(&opts) }

        guard let cursor = mongoc_collection_find_with_opts(coll, filterBson, &opts, nil) else {
            throw MongoServiceError.queryFailed("Không thể tạo cursor.")
        }
        defer { mongoc_cursor_destroy(cursor) }

        var documents: [BSONDocument] = []
        var docPtr: UnsafePointer<bson_t>?
        while mongoc_cursor_next(cursor, &docPtr) {
            if let docPtr {
                let json = bsonToCanonicalJSON(docPtr)
                if let doc = try? BSONDocument(fromJSON: json) {
                    documents.append(doc)
                }
            }
        }

        var error = bson_error_t()
        if mongoc_cursor_error(cursor, &error) {
            throw MongoServiceError.queryFailed(errorMessage(error))
        }

        return documents
    }

    private func ping(client: OpaquePointer) throws {
        var command = bson_t()
        bson_init(&command)
        bson_append_int32(&command, "ping", -1, 1)

        var reply = bson_t()
        bson_init(&reply)
        var error = bson_error_t()

        let ok = mongoc_client_command_simple(client, "admin", &command, nil, &reply, &error)
        bson_destroy(&command)
        bson_destroy(&reply)

        guard ok else {
            throw MongoServiceError.connectionFailed(errorMessage(error))
        }
    }

    private func runCommand(client: OpaquePointer, database: String, command: BSONDocument) throws -> BSONDocument {
        let json = command.toCanonicalExtendedJSONString()
        let commandBson = try bsonFromJSON(json)
        defer { bson_destroy(commandBson) }

        var reply = bson_t()
        bson_init(&reply)
        var error = bson_error_t()

        let ok = mongoc_client_command_simple(client, database, commandBson, nil, &reply, &error)
        guard ok else {
            bson_destroy(&reply)
            throw MongoServiceError.commandFailed(errorMessage(error))
        }

        let replyJSON = bsonToCanonicalJSON(&reply)
        bson_destroy(&reply)
        return try BSONDocument(fromJSON: replyJSON)
    }

    private func requireClient() throws -> OpaquePointer {
        guard let client else { throw MongoServiceError.notConnected }
        return client
    }

    private func bsonFromJSON(_ json: String) throws -> UnsafeMutablePointer<bson_t> {
        var error = bson_error_t()
        let result = json.withCString { ptr in
            bson_new_from_json(ptr, -1, &error)
        }
        guard let bson = result else {
            throw MongoServiceError.bsonError(errorMessage(error))
        }
        return bson
    }

    private func bsonToCanonicalJSON(_ bson: UnsafePointer<bson_t>) -> String {
        var length: UInt = 0
        guard let jsonPtr = bson_as_canonical_extended_json(bson, &length) else { return "{}" }
        let json = String(cString: jsonPtr)
        bson_free(jsonPtr)
        return json
    }

    private func errorMessage(_ error: bson_error_t) -> String {
        var mutableError = error
        return withUnsafePointer(to: &mutableError.message) { ptr in
            ptr.withMemoryRebound(to: CChar.self, capacity: 1) { String(cString: $0) }
        }
    }
}

enum MongoServiceError: LocalizedError {
    case notConnected
    case connectionFailed(String)
    case commandFailed(String)
    case queryFailed(String)
    case bsonError(String)

    var errorDescription: String? {
        switch self {
        case .notConnected:
            return "Chưa kết nối MongoDB."
        case .connectionFailed(let message):
            return message.isEmpty ? "Kết nối MongoDB thất bại." : message
        case .commandFailed(let message):
            return message.isEmpty ? "Lệnh MongoDB thất bại." : message
        case .queryFailed(let message):
            return message.isEmpty ? "Truy vấn MongoDB thất bại." : message
        case .bsonError(let message):
            return message.isEmpty ? "Dữ liệu BSON không hợp lệ." : message
        }
    }
}
