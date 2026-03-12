import SwiftUI
import MongoSwift

struct DatabaseDetailView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Text("Documents")
                    .font(.headline)

                if let db = appState.selectedDatabase, let collection = appState.selectedCollection {
                    Text("\(db).\(collection)")
                        .foregroundColor(.secondary)
                }

                Spacer()

                Picker("View", selection: $appState.viewMode) {
                    ForEach(DocumentViewMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 200)
            }

            HStack(spacing: 12) {
                TextField("Filter JSON, ví dụ: { \"status\": \"active\" }", text: $appState.filterText)
                    .textFieldStyle(.roundedBorder)

                Button("Run Find") {
                    guard let db = appState.selectedDatabase,
                          let collection = appState.selectedCollection else { return }
                    appState.currentPage = 0
                    Task { await appState.runFind(database: db, collection: collection) }
                }

                Button("Refresh") {
                    guard let db = appState.selectedDatabase else { return }
                    Task { await appState.refreshCollections(database: db) }
                }
            }

            HStack(spacing: 12) {
                Button("Prev") {
                    Task { await appState.previousPage() }
                }
                .disabled(appState.currentPage == 0)

                Text("Page \(appState.currentPage + 1)")
                    .foregroundColor(.secondary)

                Button("Next") {
                    Task { await appState.nextPage() }
                }
                .disabled(!appState.hasMore)

                Spacer()

                Text("Limit \(appState.pageSize)")
                    .foregroundColor(.secondary)
            }
        }
        .padding(16)
    }

    private var content: some View {
        Group {
            if appState.selectedDatabase == nil || appState.selectedCollection == nil {
                VStack {
                    Text("Chọn database và collection để xem documents.")
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if appState.viewMode == .table {
                DocumentTableView(documents: appState.documents, selection: $appState.selectedRowIds)
            } else {
                DocumentJSONView(documents: appState.documents)
            }
        }
        .background(.regularMaterial)
    }
}

struct DocumentRow: Identifiable {
    let id: String
    let document: BSONDocument

    init(document: BSONDocument, fallbackIndex: Int) {
        self.document = document
        if let rawId = document["_id"] {
            self.id = "id-\(String(describing: rawId))"
        } else {
            self.id = "row-\(fallbackIndex)"
        }
    }
}

struct DocumentTableView: View {
    let rows: [DocumentRow]
    @Binding var selection: Set<String>

    init(documents: [BSONDocument], selection: Binding<Set<String>>) {
        self.rows = documents.enumerated().map { index, doc in
            DocumentRow(document: doc, fallbackIndex: index)
        }
        self._selection = selection
    }

    private var columns: [String] {
        guard let first = rows.first else { return [] }
        return first.document.map { $0.key }
    }

    var body: some View {
        if columns.isEmpty {
            emptyState
        } else {
            Table(rows, selection: $selection) {
                TableColumnForEach(columns, id: \.self) { key in
                    TableColumn(key) { row in
                        Text(displayValue(row.document[key]))
                            .lineLimit(1)
                    }
                }
            }
            .tableStyle(.inset)
            .padding(8)
        }
    }

    private var emptyState: some View {
        VStack {
            Text("Không có document nào.")
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func displayValue(_ value: BSON?) -> String {
        guard let value else { return "" }
        return String(describing: value)
    }

}

struct DocumentJSONView: View {
    let documents: [BSONDocument]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ForEach(Array(documents.enumerated()), id: \.offset) { _, doc in
                    JSONTreeView(document: doc)
                        .padding(12)
                        .background(Color.black.opacity(0.04))
                        .cornerRadius(8)
                }
            }
            .padding(16)
        }
    }
}

struct JSONTreeView: View {
    let document: BSONDocument

    var body: some View {
        OutlineGroup(nodes, children: \.children) { node in
            HStack(spacing: 8) {
                if let key = node.key {
                    Text("\(key):")
                        .font(.system(.body, design: .monospaced))
                        .foregroundColor(.secondary)
                }
                Text(node.value)
                    .font(.system(.body, design: .monospaced))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var nodes: [JSONNode] {
        buildNodes(from: document)
    }

    private func buildNodes(from document: BSONDocument) -> [JSONNode] {
        document.map { key, value in
            JSONNode(key: key, value: value)
        }
    }
}

struct JSONNode: Identifiable {
    let id = UUID()
    let key: String?
    let value: String
    let children: [JSONNode]?

    init(key: String? = nil, value: BSON) {
        self.key = key
        switch value {
        case .document(let doc):
            self.value = "{ }"
            self.children = doc.map { JSONNode(key: $0.key, value: $0.value) }
        case .array(let array):
            self.value = "[ ]"
            self.children = array.enumerated().map { index, item in
                JSONNode(key: "[\(index)]", value: item)
            }
        default:
            self.value = String(describing: value)
            self.children = nil
        }
    }
}
