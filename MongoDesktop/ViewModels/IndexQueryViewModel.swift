import SwiftUI
import SwiftBSON

// MARK: - IndexQueryViewModel

@MainActor
final class IndexQueryViewModel: ObservableObject {

    // MARK: - State

    @Published var indexes: [BSONDocument] = []
    @Published var indexStats: [String: (size: Int64, usage: Int64)] = [:]
    @Published var isLoading = false
    @Published var error: String?

    // MARK: - Dependencies

    private let mongoService: MongoService

    init(mongoService: MongoService = .shared) {
        self.mongoService = mongoService
    }

    // MARK: - Fetch Indexes

    func fetchIndexes(database: String, collection: String, session: DatabaseSessionViewModel) async {
        isLoading = true
        error = nil

        let start = Date()

        do {
            let results = try await mongoService.listIndexes(
                database: database,
                collection: collection
            )
            let stats = (try? await mongoService.getIndexStats(
                database: database,
                collection: collection
            )) ?? [:]

            self.indexes = results
            self.indexStats = stats
            let duration = Date().timeIntervalSince(start)
            QueryHistoryStore.shared.record(
                database: database,
                collection: collection,
                queryType: .index,
                queryText: "listIndexes()",
                duration: duration,
                resultCount: results.count
            )
        } catch let err {
            let duration = Date().timeIntervalSince(start)
            self.error = err.localizedDescription
            session.lastError = err.localizedDescription
            QueryHistoryStore.shared.record(
                database: database,
                collection: collection,
                queryType: .index,
                queryText: "listIndexes()",
                duration: duration,
                isError: true,
                errorMessage: err.localizedDescription
            )
        }

        isLoading = false
    }

    // MARK: - Create Index

    func createIndex(
        database: String,
        collection: String,
        keys: BSONDocument,
        options: BSONDocument = BSONDocument(),
        session: DatabaseSessionViewModel
    ) async throws {
        isLoading = true
        error = nil
        let start = Date()

        var indexDoc: BSONDocument = [
            "key": .document(keys)
        ]
        for (k, v) in options {
            indexDoc[k] = v
        }

        let queryText = options.isEmpty
            ? "db.\(collection).createIndex(\(keys.toRelaxedExtendedJSONString()))"
            : "db.\(collection).createIndex(\(keys.toRelaxedExtendedJSONString()), \(options.toRelaxedExtendedJSONString()))"

        do {
            _ = try await mongoService.createIndexes(
                database: database,
                collection: collection,
                indexes: [indexDoc]
            )
            let duration = Date().timeIntervalSince(start)
            QueryHistoryStore.shared.record(
                database: database,
                collection: collection,
                queryType: .index,
                queryText: queryText,
                duration: duration,
                resultCount: 1
            )
            await fetchIndexes(database: database, collection: collection, session: session)
        } catch {
            let duration = Date().timeIntervalSince(start)
            self.error = error.localizedDescription
            session.lastError = error.localizedDescription
            QueryHistoryStore.shared.record(
                database: database,
                collection: collection,
                queryType: .index,
                queryText: queryText,
                duration: duration,
                isError: true,
                errorMessage: error.localizedDescription
            )
            isLoading = false
            throw error
        }
    }

    // MARK: - Drop Index

    func dropIndex(
        database: String,
        collection: String,
        name: String,
        session: DatabaseSessionViewModel
    ) async throws {
        isLoading = true
        error = nil
        let start = Date()
        let queryText = "db.\(collection).dropIndex(\"\(name)\")"

        do {
            _ = try await mongoService.dropIndex(
                database: database,
                collection: collection,
                indexName: name
            )
            let duration = Date().timeIntervalSince(start)
            QueryHistoryStore.shared.record(
                database: database,
                collection: collection,
                queryType: .index,
                queryText: queryText,
                duration: duration,
                resultCount: 1
            )
            await fetchIndexes(database: database, collection: collection, session: session)
        } catch {
            let duration = Date().timeIntervalSince(start)
            self.error = error.localizedDescription
            session.lastError = error.localizedDescription
            QueryHistoryStore.shared.record(
                database: database,
                collection: collection,
                queryType: .index,
                queryText: queryText,
                duration: duration,
                isError: true,
                errorMessage: error.localizedDescription
            )
            isLoading = false
            throw error
        }
    }

    // MARK: - Clear

    func clear() {
        indexes = []
        indexStats = [:]
        error = nil
    }
}
