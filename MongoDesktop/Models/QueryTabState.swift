import SwiftUI
import SwiftBSON

// MARK: - QueryTabState (per-tab)

@MainActor
final class QueryTabState: ObservableObject {
    @Published var title: String = ""
    @Published var databaseName: String?
    @Published var collectionName: String?
    @Published var filterText: String = "{}"
    @Published var sortText: String = "{}"
    @Published var projectionText: String = "{}"
    @Published var isAdvancedQuery: Bool = false
    @Published var viewMode: DocumentViewMode = .json
    @Published var pageSize: Int = 100
    @Published var currentPage: Int = 0
    @Published var hasMore: Bool = false
    @Published var documents: [BSONDocument] = []
    @Published var selectedRowIds: Set<String> = []
    @Published var isLoading: Bool = false
    @Published var lastQueryDuration: TimeInterval? = nil

    func resetPaging() {
        currentPage = 0
    }

    func runFind(appState: AppState) async {
        guard let db = databaseName ?? appState.selectedDatabase,
              let collection = collectionName ?? appState.selectedCollection else { return }
        // Ensure state is so tab displays correctly
        if self.databaseName == nil { self.databaseName = db }
        if self.collectionName == nil { self.collectionName = collection }
        await runFind(database: db, collection: collection, appState: appState)
    }

    func runFind(database: String, collection: String, appState: AppState) async {
        isLoading = true
        title = collection
        appState.lastError = nil
        lastQueryDuration = nil
        let start = Date()
        do {
            let filter = try parseFilter(filterText)
            let sort = isAdvancedQuery ? try parseQueryOption(sortText) : nil
            let projection = isAdvancedQuery ? try parseQueryOption(projectionText) : nil
            let skip = currentPage * pageSize
            let docs = try await MongoService.shared.findDocuments(
                database: database, collection: collection,
                filter: filter, sort: sort, projection: projection,
                limit: pageSize, skip: skip
            )
            let elapsed = Date().timeIntervalSince(start)
            documents = docs
            hasMore = docs.count == pageSize
            selectedRowIds = []
            lastQueryDuration = elapsed
            isLoading = false
        } catch {
            appState.lastError = error.localizedDescription
            isLoading = false
        }
    }

    func nextPage(appState: AppState) async {
        guard hasMore else { return }
        currentPage += 1
        await runFind(appState: appState)
    }

    func previousPage(appState: AppState) async {
        guard currentPage > 0 else { return }
        currentPage -= 1
        await runFind(appState: appState)
    }

    private func parseFilter(_ text: String) throws -> BSONDocument {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed == "{}" { return BSONDocument() }
        return try BSONDocument(fromJSON: trimmed)
    }

    private func parseQueryOption(_ text: String) throws -> BSONDocument? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed == "{}" { return nil }
        return try BSONDocument(fromJSON: trimmed)
    }
}
