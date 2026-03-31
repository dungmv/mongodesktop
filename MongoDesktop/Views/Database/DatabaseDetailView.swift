import Foundation
import SwiftUI
import SwiftBSON

// MARK: - DatabaseDetailView

struct DatabaseDetailView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var tabState: QueryTabState
    @EnvironmentObject private var globalSettings: GlobalSettings
    @Environment(\.databaseTabContext) private var tabContext
    @State private var filterError: String? = nil
    @State private var sortError: String? = nil
    @State private var projectionError: String? = nil

    var body: some View {
        VStack(spacing: 0) {
            if let tabContext {
                if tabContext.tabs.count > 1 {
                    tabBar(tabContext)
                }
            }
            toolbarArea
            Divider()
                .opacity(0.4)
            contentArea
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.ultraThinMaterial)
    }

    // MARK: Toolbar Area
    private var toolbarArea: some View {
        VStack(spacing: 0) {
            // Filter Row
            HStack(spacing: 8) {
                Image(systemName: "line.3.horizontal.decrease.circle")
                    .foregroundStyle(.secondary)
                    .font(.body)

                JSONEditorView(
                    text: $tabState.filterText,
                    errorMessage: $filterError,
                    minHeight: 28
                )
                .frame(maxWidth: .infinity)
                .frame(height: 28)
                .overlay {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(filterError == nil ? Color.secondary.opacity(0.35) : .red.opacity(0.7), lineWidth: 1)
                }
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                .help(filterError ?? "Filter JSON { \"field\": \"value\" }")

                Button(action: { withAnimation(.easeInOut(duration: 0.2)) { tabState.isAdvancedQuery.toggle() } }) {
                    Label(tabState.isAdvancedQuery ? "Simple" : "Advanced", systemImage: "slider.horizontal.3")
                        .font(.caption.weight(.medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button(action: runFind) {
                    Label("Run", systemImage: "play.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.return, modifiers: [.command])
                .disabled(hasSyntaxError)
                .opacity(hasSyntaxError ? 0.55 : 1)

            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            if tabState.isAdvancedQuery {
                advancedQueryRow
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
            }

            Divider()
                .opacity(0.4)

            // Pagination Row
            paginationRow
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
        }
    }

    private var advancedQueryRow: some View {
        HStack(spacing: 10) {
            Text("Sort")
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)

            JSONEditorView(
                text: $tabState.sortText,
                errorMessage: $sortError,
                minHeight: 28
            )
            .frame(maxWidth: .infinity)
            .frame(height: 28)
            .overlay {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(sortError == nil ? Color.secondary.opacity(0.35) : .red.opacity(0.7), lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            .help(sortError ?? "Sort JSON { \"field\": 1 }")

            Text("Projection")
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)

            JSONEditorView(
                text: $tabState.projectionText,
                errorMessage: $projectionError,
                minHeight: 28
            )
            .frame(maxWidth: .infinity)
            .frame(height: 28)
            .overlay {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(projectionError == nil ? Color.secondary.opacity(0.35) : .red.opacity(0.7), lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            .help(projectionError ?? "Projection JSON { \"field\": 1 }")
        }
    }



    // MARK: View Mode Picker
    private var viewModePicker: some View {
        Picker("", selection: $tabState.viewMode) {
            ForEach(DocumentViewMode.allCases) { mode in
                Image(systemName: mode == .table ? "tablecells" : "curlybraces")
                    .tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .frame(width: 70)
    }

    // MARK: Pagination
    private var paginationRow: some View {
        HStack(spacing: 12) {
            Button(action: { Task { await tabState.previousPage(appState: appState) } }) {
                Image(systemName: "chevron.left")
                    .font(.caption.weight(.semibold))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(tabState.currentPage == 0)

            Text("Trang \(tabState.currentPage + 1)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()

            Button(action: { Task { await tabState.nextPage(appState: appState) } }) {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(!tabState.hasMore)

            Divider()
                .frame(height: 14)
                .padding(.horizontal, 4)

            Text("\(tabState.documents.count) docs")
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()

            Spacer()

            Text("Giới hạn \(tabState.pageSize)")
                .font(.caption)
                .foregroundStyle(.tertiary)
            
            viewModePicker
        }
    }

    // MARK: Content Area
    private var contentArea: some View {
        Group {
            if appState.selectedDatabase == nil || appState.selectedCollection == nil {
                VStack {
                    ContentUnavailableView(
                        "Chọn một collection",
                        systemImage: "tablecells",
                        description: Text("Chọn database và collection từ sidebar để xem documents.")
                    )
                    .padding(.top, 40)
                    Spacer()
                }
            } else if tabState.viewMode == .table {
                DocumentTableView(documents: tabState.documents, selection: $tabState.selectedRowIds)
            } else {
                DocumentJSONView(documents: tabState.documents, timeZone: globalSettings.displayTimeZone)
            }
        }
    }

    // MARK: Actions
    private func runFind() {
        guard !hasSyntaxError else { return }
        tabState.resetPaging()
        Task { await tabState.runFind(appState: appState) }
    }

    private var hasSyntaxError: Bool {
        if filterError != nil { return true }
        if tabState.isAdvancedQuery && (sortError != nil || projectionError != nil) { return true }
        return false
    }

    private func tabBar(_ context: DatabaseTabContext) -> some View {
        ScrollView(.horizontal, showsIndicators: true) {
            HStack(spacing: 8) {
                ForEach(context.tabs) { tab in
                    TabPill(
                        title: tab.title,
                        isSelected: tab.id == context.selectedId,
                        onSelect: { context.select(tab.id) },
                        onClose: { context.close(tab.id) }
                    )
                }
                Button(action: context.add) {
                    Image(systemName: "plus")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 22, height: 22)
                        .background(Circle().fill(Color.secondary.opacity(0.12)))
                }
                .buttonStyle(.plain)
                .help("New Tab")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .overlay(alignment: .bottom) {
            Divider().opacity(0.3)
        }
    }
}

private struct TabPill: View {
    let title: String
    let isSelected: Bool
    let onSelect: () -> Void
    let onClose: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Button(action: onSelect) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(isSelected ? .primary : .secondary)
                    .lineLimit(1)
            }
            .buttonStyle(.plain)

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 14, height: 14)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule(style: .continuous)
                .fill(isSelected ? Color.primary.opacity(0.12) : Color.secondary.opacity(0.08))
        )
        .overlay(
            Capsule(style: .continuous)
                .stroke(Color.primary.opacity(isSelected ? 0.22 : 0.12), lineWidth: 1)
        )
    }
}

// MARK: - DocumentRow

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

// MARK: - DocumentTableView

struct DocumentTableView: View {
    @EnvironmentObject private var globalSettings: GlobalSettings
    let rows: [DocumentRow]
    @Binding var selection: Set<String>

    init(documents: [BSONDocument], selection: Binding<Set<String>>) {
        self.rows = documents.enumerated().map { index, doc in
            DocumentRow(document: doc, fallbackIndex: index)
        }
        self._selection = selection
    }

    private var columns: [String] {
        guard !rows.isEmpty else { return [] }
        var keys = Set<String>()
        for row in rows {
            for pair in row.document {
                keys.insert(pair.key)
            }
        }
        if keys.isEmpty { return [] }
        return keys.sorted { lhs, rhs in
            if lhs == "_id" { return true }
            if rhs == "_id" { return false }
            return lhs.localizedStandardCompare(rhs) == .orderedAscending
        }
    }

    private func typeString(for key: String) -> String {
        var observedTypes = Set<String>()
        for row in rows {
            if let value = row.document[key] {
                observedTypes.insert(typeName(for: value))
            }
        }
        if observedTypes.isEmpty { return "Unknown" }
        if observedTypes.count == 1 { return observedTypes.first! }
        return "Mixed"
    }

    private func typeName(for value: BSON) -> String {
        switch value {
        case .double: return "Double"
        case .string: return "String"
        case .document: return "Object"
        case .array: return "Array"
        case .binary: return "Binary"
        case .objectID: return "ObjectId"
        case .bool: return "Bool"
        case .datetime: return "Date"
        case .null: return "Null"
        case .regex: return "Regex"
        case .int32: return "Int32"
        case .timestamp: return "Timestamp"
        case .int64: return "Int64"
        case .decimal128: return "Decimal"
        case .maxKey: return "MaxKey"
        case .minKey: return "MinKey"
        default: return "Unknown"
        }
    }

    var body: some View {
        if columns.isEmpty {
            VStack {
                ContentUnavailableView(
                    "Không có document",
                    systemImage: "doc.text",
                    description: Text("Collection này chưa có dữ liệu hoặc filter không khớp.")
                )
                .padding(.top, 40)
                Spacer()
            }
        } else {
            Table(rows, selection: $selection) {
                TableColumnForEach(columns, id: \.self) { key in
                    TableColumn("\(key) \(typeString(for: key))") { row in
                        Text(displayValue(row.document[key], timeZone: globalSettings.displayTimeZone))
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }
            }
            .tableStyle(.inset(alternatesRowBackgrounds: true))
            .id(columns)
        }
    }

}

fileprivate let displayDateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssXXXXX"
    return formatter
}()

fileprivate func displayValue(_ value: BSON?, timeZone: TimeZone) -> String {
    guard let value else { return "" }
    switch value {
    case .document(let doc):
        return "{} \(doc.count) fields"
    case .array(let arr):
        return "[] \(arr.count) items"
    case .string(let s):
        return s
    case .double(let d):
        return String(d)
    case .int32(let i):
        return String(i)
    case .int64(let i):
        return String(i)
    case .bool(let b):
        return String(b)
    case .null:
        return "null"
    case .datetime(let d):
        displayDateFormatter.timeZone = timeZone
        return displayDateFormatter.string(from: d)
    default:
        return String(describing: value)
    }
}

// MARK: - DocumentJSONView

struct DocumentJSONView: View {
    let documents: [BSONDocument]
    let timeZone: TimeZone

    var body: some View {
        if documents.isEmpty {
            VStack {
                ContentUnavailableView(
                    "Không có document",
                    systemImage: "curlybraces",
                    description: Text("Collection này chưa có dữ liệu hoặc filter không khớp.")
                )
                .padding(.top, 40)
                Spacer()
            }
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(documents.enumerated()), id: \.offset) { index, doc in
                        JSONDocumentCard(index: index, document: doc, timeZone: timeZone)
                    }
                }
                .padding(16)
            }
        }
    }
}

// MARK: - JSONDocumentCard

struct JSONDocumentCard: View {
    let index: Int
    let document: BSONDocument
    let timeZone: TimeZone

    private var nodes: [JSONNode] {
        document.map { JSONNode(key: $0.key, value: $0.value, timeZone: timeZone) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Divider().opacity(0.4)

            VStack(alignment: .leading, spacing: 3) {
                ForEach(nodes) { node in
                    JSONNodeView(node: node, depth: 0)
                }
            }
            .padding(12)
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.primary.opacity(0.07), lineWidth: 1)
        )
    }
}

// MARK: - JSONTreeView

struct JSONTreeView: View {
    let document: BSONDocument
    let timeZone: TimeZone

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(nodes) { node in
                JSONNodeView(node: node, depth: 0)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var nodes: [JSONNode] {
        document.map { JSONNode(key: $0.key, value: $0.value, timeZone: timeZone) }
    }
}

// MARK: - JSONNode

struct JSONNode: Identifiable {
    let id = UUID()
    let key: String?
    let value: String
    let children: [JSONNode]?
    let rawValue: BSON

    init(key: String? = nil, value: BSON, timeZone: TimeZone) {
        self.key = key
        self.rawValue = value
        switch value {
        case .document(let doc):
            self.value = "{ \(doc.count) fields }"
            self.children = doc.map { JSONNode(key: $0.key, value: $0.value, timeZone: timeZone) }
        case .array(let array):
            self.value = "[ \(array.count) items ]"
            self.children = array.enumerated().map { index, item in
                JSONNode(key: "[\(index)]", value: item, timeZone: timeZone)
            }
        default:
            self.value = displayValue(value, timeZone: timeZone)
            self.children = nil
        }
    }
}

// MARK: - JSONNodeView

struct JSONNodeView: View {
    let node: JSONNode
    let depth: Int
    @State private var isExpanded: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                // Indent
                if depth > 0 {
                    Rectangle()
                        .fill(Color.primary.opacity(0.1))
                        .frame(width: 1)
                        .padding(.horizontal, 7)
                }

                if node.children != nil {
                    Button(action: { withAnimation(.spring(duration: 0.2)) { isExpanded.toggle() } }) {
                        Image(systemName: isExpanded ? "chevron.down.circle.fill" : "chevron.right.circle.fill")
                            .font(.caption)
                            .foregroundStyle(Color.accentColor.opacity(0.7))
                    }
                    .buttonStyle(.plain)
                } else {
                    Circle()
                        .fill(Color.primary.opacity(0.2))
                        .frame(width: 5, height: 5)
                        .padding(.horizontal, 4)
                }

                if let key = node.key {
                    Text("\(key):")
                        .font(.system(.callout, design: .monospaced))
                        .foregroundStyle(Color(red: 0.4, green: 0.7, blue: 1.0))
                }

                Text(node.value)
                    .font(.system(.callout, design: .monospaced))
                    .foregroundStyle(valueColor)
                    .textSelection(.enabled)
                    .lineLimit(1)
            }
            .padding(.leading, CGFloat(depth) * 16)

            if isExpanded, let children = node.children {
                ForEach(children) { child in
                    JSONNodeView(node: child, depth: depth + 1)
                }
            }
        }
    }

    private var valueColor: Color {
        if node.children != nil { return .secondary }
        switch node.rawValue {
        case .string: return Color(red: 0.8, green: 0.6, blue: 0.3)
        case .bool: return Color(red: 0.4, green: 0.85, blue: 0.5)
        case .null: return Color(red: 0.7, green: 0.4, blue: 0.4)
        case .int32, .int64, .double, .decimal128: return Color(red: 0.6, green: 0.85, blue: 0.7)
        default: return .primary
        }
    }
}
