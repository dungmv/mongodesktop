import SwiftUI
import SwiftBSON

// MARK: - EditableBSONType

enum EditableBSONType: String, CaseIterable, Identifiable {
    case string = "String"
    case int32 = "Int32"
    case int64 = "Int64"
    case double = "Double"
    case bool = "Boolean"
    case objectID = "ObjectId"
    case date = "Date"
    case document = "Object"
    case array = "Array"
    case null = "Null"

    var id: String { rawValue }

    var color: Color {
        switch self {
        case .string:
            return Color(red: 0.8, green: 0.6, blue: 0.3)
        case .int32, .int64, .double:
            return Color(red: 0.6, green: 0.85, blue: 0.7)
        case .bool:
            return Color(red: 0.4, green: 0.85, blue: 0.5)
        case .objectID, .date:
            return .orange
        case .null:
            return Color(red: 0.7, green: 0.4, blue: 0.4)
        case .document, .array:
            return Color(red: 0.4, green: 0.7, blue: 1.0)
        }
    }
}

// MARK: - EditableBSONNode

final class EditableBSONNode: Identifiable, ObservableObject {
    let id: UUID
    @Published var key: String
    @Published var type: EditableBSONType
    @Published var valueString: String
    @Published var children: [EditableBSONNode]
    @Published var isExpanded: Bool
    let isKeyEditable: Bool
    let parentIsArray: Bool
    let isPrimaryKey: Bool

    init(
        id: UUID = UUID(),
        key: String,
        type: EditableBSONType,
        valueString: String = "",
        children: [EditableBSONNode] = [],
        isExpanded: Bool = false,
        isKeyEditable: Bool = false,
        parentIsArray: Bool = false,
        isPrimaryKey: Bool = false
    ) {
        self.id = id
        self.key = key
        self.type = type
        self.valueString = valueString
        self.children = children
        self.isExpanded = isExpanded
        self.isKeyEditable = isKeyEditable
        self.parentIsArray = parentIsArray
        self.isPrimaryKey = isPrimaryKey
    }

    func changeType(to newType: EditableBSONType) {
        guard !isPrimaryKey else { return }
        guard type != newType else { return }
        type = newType
        switch newType {
        case .document:
            valueString = ""
            if children.isEmpty {
                children = [EditableBSONNode(key: "newField", type: .string, valueString: "", isKeyEditable: true)]
            }
            isExpanded = true
        case .array:
            valueString = ""
            if children.isEmpty {
                children = [EditableBSONNode(key: "[0]", type: .string, valueString: "", isKeyEditable: false, parentIsArray: true)]
            }
            isExpanded = true
        case .bool:
            valueString = "true"
            children.removeAll()
        case .null:
            valueString = "null"
            children.removeAll()
        case .int32, .int64:
            if Int(valueString) == nil { valueString = "0" }
            children.removeAll()
        case .double:
            if Double(valueString) == nil { valueString = "0.0" }
            children.removeAll()
        case .objectID:
            if valueString.count != 24 {
                valueString = BSONObjectID().hex
            }
            children.removeAll()
        case .date:
            let formatter = ISO8601DateFormatter()
            valueString = formatter.string(from: Date())
            children.removeAll()
        case .string:
            children.removeAll()
        }
        objectWillChange.send()
    }

    func addChildField() {
        guard type == .document else { return }
        var baseName = "newField"
        var counter = 1
        let existingKeys = Set(children.map(\.key))
        while existingKeys.contains(baseName) {
            baseName = "newField\(counter)"
            counter += 1
        }
        let child = EditableBSONNode(
            key: baseName,
            type: .string,
            valueString: "",
            isKeyEditable: true,
            parentIsArray: false
        )
        children.append(child)
        isExpanded = true
        objectWillChange.send()
    }

    func addChildElement() {
        guard type == .array else { return }
        let nextIndex = children.count
        let child = EditableBSONNode(
            key: "[\(nextIndex)]",
            type: .string,
            valueString: "",
            isKeyEditable: false,
            parentIsArray: true
        )
        children.append(child)
        isExpanded = true
        objectWillChange.send()
    }

    func removeChild(_ childID: UUID) {
        children.removeAll { $0.id == childID }
        if type == .array {
            reindexArrayChildren()
        }
        objectWillChange.send()
    }

    private func reindexArrayChildren() {
        for (idx, child) in children.enumerated() {
            child.key = "[\(idx)]"
        }
    }

    func toBSON() -> BSON {
        switch type {
        case .string:
            return .string(valueString)
        case .int32:
            return .int32(Int32(valueString) ?? 0)
        case .int64:
            return .int64(Int64(valueString) ?? 0)
        case .double:
            return .double(Double(valueString) ?? 0.0)
        case .bool:
            return .bool(valueString.lowercased() == "true")
        case .null:
            return .null
        case .objectID:
            if let oid = try? BSONObjectID(valueString) {
                return .objectID(oid)
            } else if let doc = try? BSONDocument(fromJSON: "{\"v\": {\"$oid\": \"\(valueString)\"}}"),
                      let val = doc["v"] {
                return val
            } else {
                return .string(valueString)
            }
        case .date:
            let formatter = ISO8601DateFormatter()
            if let d = formatter.date(from: valueString) {
                return .datetime(d)
            } else if let doc = try? BSONDocument(fromJSON: "{\"v\": {\"$date\": \"\(valueString)\"}}"),
                      let val = doc["v"] {
                return val
            } else {
                return .string(valueString)
            }
        case .document:
            var doc = BSONDocument()
            for child in children {
                let trimmed = child.key.trimmingCharacters(in: .whitespaces)
                guard !trimmed.isEmpty else { continue }
                doc[trimmed] = child.toBSON()
            }
            return .document(doc)
        case .array:
            var arr: [BSON] = []
            for child in children {
                arr.append(child.toBSON())
            }
            return .array(arr)
        }
    }

    static func fromBSONDocument(_ doc: BSONDocument, timeZone: TimeZone) -> [EditableBSONNode] {
        var nodes: [EditableBSONNode] = []
        var idNode: EditableBSONNode? = nil

        for (key, value) in doc {
            let isPrimaryKey = (key == "_id")
            let node = fromBSONValue(
                key: key,
                value: value,
                timeZone: timeZone,
                isKeyEditable: false,
                parentIsArray: false,
                isPrimaryKey: isPrimaryKey
            )
            if isPrimaryKey {
                idNode = node
            } else {
                nodes.append(node)
            }
        }

        // Ensure _id is ALWAYS at the top
        if let idNode {
            nodes.insert(idNode, at: 0)
        }

        return nodes
    }

    static func fromBSONValue(
        key: String,
        value: BSON,
        timeZone: TimeZone,
        isKeyEditable: Bool,
        parentIsArray: Bool,
        isPrimaryKey: Bool = false
    ) -> EditableBSONNode {
        switch value {
        case .document(let doc):
            let children = doc.map { k, v in
                fromBSONValue(
                    key: k,
                    value: v,
                    timeZone: timeZone,
                    isKeyEditable: false,
                    parentIsArray: false
                )
            }
            return EditableBSONNode(
                key: key,
                type: .document,
                valueString: "",
                children: children,
                isExpanded: false,
                isKeyEditable: isKeyEditable,
                parentIsArray: parentIsArray,
                isPrimaryKey: isPrimaryKey
            )
        case .array(let arr):
            let children = arr.enumerated().map { idx, v in
                fromBSONValue(
                    key: "[\(idx)]",
                    value: v,
                    timeZone: timeZone,
                    isKeyEditable: false,
                    parentIsArray: true
                )
            }
            return EditableBSONNode(
                key: key,
                type: .array,
                valueString: "",
                children: children,
                isExpanded: false,
                isKeyEditable: false,
                parentIsArray: true,
                isPrimaryKey: false
            )
        case .string(let s):
            return EditableBSONNode(key: key, type: .string, valueString: s, isKeyEditable: isKeyEditable, parentIsArray: parentIsArray, isPrimaryKey: isPrimaryKey)
        case .int32(let i):
            return EditableBSONNode(key: key, type: .int32, valueString: String(i), isKeyEditable: isKeyEditable, parentIsArray: parentIsArray, isPrimaryKey: isPrimaryKey)
        case .int64(let i):
            return EditableBSONNode(key: key, type: .int64, valueString: String(i), isKeyEditable: isKeyEditable, parentIsArray: parentIsArray, isPrimaryKey: isPrimaryKey)
        case .double(let d):
            return EditableBSONNode(key: key, type: .double, valueString: String(d), isKeyEditable: isKeyEditable, parentIsArray: parentIsArray, isPrimaryKey: isPrimaryKey)
        case .bool(let b):
            return EditableBSONNode(key: key, type: .bool, valueString: String(b), isKeyEditable: isKeyEditable, parentIsArray: parentIsArray, isPrimaryKey: isPrimaryKey)
        case .null:
            return EditableBSONNode(key: key, type: .null, valueString: "null", isKeyEditable: isKeyEditable, parentIsArray: parentIsArray, isPrimaryKey: isPrimaryKey)
        case .objectID(let oid):
            return EditableBSONNode(key: key, type: .objectID, valueString: "\(oid)", isKeyEditable: isKeyEditable, parentIsArray: parentIsArray, isPrimaryKey: isPrimaryKey)
        case .datetime(let d):
            let formatter = ISO8601DateFormatter()
            return EditableBSONNode(key: key, type: .date, valueString: formatter.string(from: d), isKeyEditable: isKeyEditable, parentIsArray: parentIsArray, isPrimaryKey: isPrimaryKey)
        default:
            return EditableBSONNode(key: key, type: .string, valueString: displayValue(value, timeZone: timeZone), isKeyEditable: isKeyEditable, parentIsArray: parentIsArray, isPrimaryKey: isPrimaryKey)
        }
    }
}

// MARK: - EditableDocumentOutlineView

struct EditableDocumentOutlineView: View {
    let originalDocument: BSONDocument
    let timeZone: TimeZone
    let onSave: (BSONDocument) async -> Bool
    let onCancel: () -> Void

    @State private var rootNodes: [EditableBSONNode] = []
    @State private var isSaving: Bool = false
    @State private var errorMessage: String? = nil

    init(
        originalDocument: BSONDocument,
        timeZone: TimeZone,
        onSave: @escaping (BSONDocument) async -> Bool,
        onCancel: @escaping () -> Void
    ) {
        self.originalDocument = originalDocument
        self.timeZone = timeZone
        self.onSave = onSave
        self.onCancel = onCancel
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header: Editing indicator & Tree actions
            HStack(spacing: 8) {
                Label("Outline Tree Editor", systemImage: "list.bullet.indent")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.accentColor)

                Spacer()

                Button(action: addRootField) {
                    Label("Add Field", systemImage: "plus")
                        .font(.caption2.weight(.medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
                .help("Add new field to document")
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)

            Divider().opacity(0.5)

            // Outline Tree Rows
            VStack(alignment: .leading, spacing: 4) {
                ForEach(rootNodes) { node in
                    EditableBSONRowView(
                        node: node,
                        depth: 0,
                        isRootNode: true,
                        onDelete: {
                            removeRootNode(node.id)
                        }
                    )
                }
            }
            .padding(.horizontal, 12)

            if let errorMessage {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .font(.caption2)
                    Text(errorMessage)
                        .font(.caption2)
                        .foregroundStyle(.red)
                        .lineLimit(2)
                    Spacer()
                }
                .padding(.horizontal, 12)
            }

            Divider().opacity(0.5)

            // Footer Bar: Cancel and Save buttons
            HStack(spacing: 10) {
                Spacer()

                Button("Cancel", action: onCancel)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(isSaving)

                Button(action: saveDocument) {
                    Group {
                        if isSaving {
                            ProgressView()
                                .scaleEffect(0.6)
                                .frame(width: 14, height: 14)
                        } else {
                            Label("Save", systemImage: "checkmark")
                                .font(.caption.weight(.semibold))
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .foregroundColor(.white)
                }
                .buttonStyle(.plain)
                .disabled(isSaving)
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 10)
        }
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.6))
        }
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.accentColor.opacity(0.4), lineWidth: 1.5)
        )
        .onAppear {
            rootNodes = EditableBSONNode.fromBSONDocument(originalDocument, timeZone: timeZone)
        }
    }

    private func addRootField() {
        var baseName = "newField"
        var counter = 1
        let existingKeys = Set(rootNodes.map(\.key))
        while existingKeys.contains(baseName) {
            baseName = "newField\(counter)"
            counter += 1
        }
        let newNode = EditableBSONNode(
            key: baseName,
            type: .string,
            valueString: "",
            isKeyEditable: true,
            parentIsArray: false,
            isPrimaryKey: false
        )
        rootNodes.append(newNode)
    }

    private func removeRootNode(_ nodeID: UUID) {
        rootNodes.removeAll { $0.id == nodeID && !$0.isPrimaryKey }
    }

    private func saveDocument() {
        var updatedDoc = BSONDocument()
        for node in rootNodes {
            let key = node.key.trimmingCharacters(in: .whitespaces)
            guard !key.isEmpty else {
                errorMessage = "Field name cannot be empty."
                return
            }
            updatedDoc[key] = node.toBSON()
        }

        // Ensure original _id is strictly preserved
        if let origId = originalDocument["_id"] {
            updatedDoc["_id"] = origId
        }

        isSaving = true
        errorMessage = nil

        Task {
            let success = await onSave(updatedDoc)
            if !success {
                isSaving = false
                errorMessage = "Failed to update document. Please check values."
            }
        }
    }
}

// MARK: - EditableBSONRowView

struct EditableBSONRowView: View {
    @ObservedObject var node: EditableBSONNode
    let depth: Int
    var isRootNode: Bool = false
    let onDelete: () -> Void

    var isIdField: Bool {
        node.isPrimaryKey || (isRootNode && node.key == "_id")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                // Indentation
                if depth > 0 {
                    Spacer()
                        .frame(width: CGFloat(depth) * 16)
                }

                // Expand/Collapse Chevron (for Object / Array)
                if !isIdField && (node.type == .document || node.type == .array) {
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            node.isExpanded.toggle()
                        }
                    }) {
                        Image(systemName: node.isExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(Color.accentColor.opacity(0.85))
                            .frame(width: 14, height: 14)
                    }
                    .buttonStyle(.plain)
                } else {
                    Spacer()
                        .frame(width: 14, height: 14)
                }

                // Key display
                if isIdField {
                    HStack(spacing: 4) {
                        Image(systemName: "key.fill")
                            .font(.system(size: 8))
                            .foregroundStyle(.orange)
                        Text("_id")
                            .font(.system(.caption, design: .monospaced).weight(.bold))
                            .foregroundStyle(Color(red: 0.4, green: 0.7, blue: 1.0))
                    }
                } else if node.isKeyEditable {
                    // Only newly added fields have editable key
                    TextField("field", text: $node.key)
                        .textFieldStyle(.plain)
                        .font(.system(.caption, design: .monospaced))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 4))
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(Color.accentColor.opacity(0.4), lineWidth: 0.8)
                        )
                        .frame(minWidth: 60, maxWidth: 140)
                } else {
                    // Existing keys are strictly read-only text labels
                    Text(node.key)
                        .font(.system(.caption, design: .monospaced).weight(.semibold))
                        .foregroundStyle(node.parentIsArray ? .secondary : Color(red: 0.4, green: 0.7, blue: 1.0))
                }

                Text(":")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)

                // Type Display / Picker
                if isIdField {
                    // Read-only type badge for _id
                    Text(node.type.rawValue)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(node.type.color)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(node.type.color.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
                } else {
                    // Type Picker Menu for non-_id fields
                    Menu {
                        ForEach(EditableBSONType.allCases) { t in
                            Button(t.rawValue) {
                                node.changeType(to: t)
                            }
                        }
                    } label: {
                        HStack(spacing: 3) {
                            Text(node.type.rawValue)
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(node.type.color)
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.system(size: 7))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(node.type.color.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                }

                // Value field based on type
                if isIdField {
                    // Read-only selectable value for _id
                    Text(node.valueString)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    valueView
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                // Add child button (for Object or Array)
                if !isIdField {
                    if node.type == .document {
                        Button(action: { node.addChildField() }) {
                            Image(systemName: "plus")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(Color.accentColor)
                                .frame(width: 18, height: 18)
                        }
                        .buttonStyle(.plain)
                        .help("Add field to this object")
                    } else if node.type == .array {
                        Button(action: { node.addChildElement() }) {
                            Image(systemName: "plus")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(Color.accentColor)
                                .frame(width: 18, height: 18)
                        }
                        .buttonStyle(.plain)
                        .help("Add item to this array")
                    }

                    // Delete node button
                    Button(action: onDelete) {
                        Image(systemName: "trash")
                            .font(.system(size: 10))
                            .foregroundStyle(.red.opacity(0.75))
                            .frame(width: 18, height: 18)
                    }
                    .buttonStyle(.plain)
                    .help("Delete this field")
                }
            }
            .padding(.vertical, 2)

            // Children nodes if expanded
            if !isIdField && node.isExpanded && (node.type == .document || node.type == .array) {
                ForEach(node.children) { child in
                    EditableBSONRowView(
                        node: child,
                        depth: depth + 1,
                        isRootNode: false,
                        onDelete: {
                            node.removeChild(child.id)
                        }
                    )
                }
            }
        }
    }

    @ViewBuilder
    private var valueView: some View {
        switch node.type {
        case .document:
            Text("{ \(node.children.count) fields }")
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
        case .array:
            Text("[ \(node.children.count) items ]")
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
        case .null:
            Text("null")
                .font(.caption.monospaced())
                .foregroundStyle(Color(red: 0.7, green: 0.4, blue: 0.4))
        case .bool:
            Picker("", selection: $node.valueString) {
                Text("true").tag("true")
                Text("false").tag("false")
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 90)
        default:
            TextField("value", text: $node.valueString)
                .textFieldStyle(.plain)
                .font(.system(.caption, design: .monospaced))
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 4))
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color.primary.opacity(0.12), lineWidth: 0.8)
                )
        }
    }
}
