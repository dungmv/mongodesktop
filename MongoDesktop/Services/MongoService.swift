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

        let newClient = try createClient(uri: uri)

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
        let tempClient = try createClient(uri: uri)
        defer { mongoc_client_destroy(tempClient) }
        try ping(client: tempClient)
    }

    func debugDNS(uri: String) async -> String {
        await DNSDebugService.debug(uri: uri)
    }

    func debugConnection(uri: String) async -> String {
        ensureInitialized()
        let redacted = redactedURI(uri)
        var lines: [String] = []
        lines.append("Mongo Connection Debug")
        lines.append("URI: \(redacted)")
        lines.append("isSRV: \(uri.lowercased().hasPrefix("mongodb+srv://"))")
        var error = bson_error_t()
        if let parsed = mongoc_uri_new_with_error(uri, &error) {
            mongoc_uri_destroy(parsed)
            lines.append("Parse URI: OK")
        } else {
            lines.append("Parse URI: FAILED")
            let msg = errorMessage(error)
            lines.append("Error: \(msg.isEmpty ? "(empty)" : msg)")
            lines.append("Domain: \(error.domain)  Code: \(error.code)")
        }
        // Try create client to surface any SRV resolution / option issues.
        var createError = bson_error_t()
        if let parsed = mongoc_uri_new_with_error(uri, &createError) {
            let client = mongoc_client_new_from_uri_with_error(parsed, &createError)
            if let client {
                mongoc_client_destroy(client)
                lines.append("Create Client: OK")
            } else {
                let msg = errorMessage(createError)
                lines.append("Create Client: FAILED")
                lines.append("Error: \(msg.isEmpty ? "(empty)" : msg)")
                lines.append("Domain: \(createError.domain)  Code: \(createError.code)")
            }
            mongoc_uri_destroy(parsed)
        }
        return lines.joined(separator: "\n")
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

    private func createClient(uri: String) throws -> OpaquePointer {
        var error = bson_error_t()
        guard let parsed = mongoc_uri_new_with_error(uri, &error) else {
            let msg = errorMessage(error)
            let detail = msg.isEmpty ? "Không thể parse URI." : "Không thể parse URI: \(msg)"
            throw MongoServiceError.connectionFailed("\(detail)\nURI: \(redactedURI(uri))\nDomain: \(error.domain)  Code: \(error.code)")
        }
        defer { mongoc_uri_destroy(parsed) }

        var createError = bson_error_t()
        guard let client = mongoc_client_new_from_uri_with_error(parsed, &createError) else {
            let msg = errorMessage(createError)
            let detail = msg.isEmpty ? "Không thể khởi tạo Mongo client." : "Không thể khởi tạo Mongo client: \(msg)"
            throw MongoServiceError.connectionFailed("\(detail)\nURI: \(redactedURI(uri))\nDomain: \(createError.domain)  Code: \(createError.code)")
        }
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

    private func redactedURI(_ uri: String) -> String {
        guard let schemeRange = uri.range(of: "://") else { return uri }
        let scheme = uri[..<schemeRange.upperBound]
        let rest = uri[schemeRange.upperBound...]
        guard let atIndex = rest.firstIndex(of: "@") else { return uri }
        let userInfo = rest[..<atIndex]
        let hostAndPath = rest[atIndex...]
        if let colonIndex = userInfo.firstIndex(of: ":") {
            let user = userInfo[..<colonIndex]
            return "\(scheme)\(user):******\(hostAndPath)"
        }
        return "\(scheme)\(userInfo)\(hostAndPath)"
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
