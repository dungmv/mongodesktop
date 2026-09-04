import SwiftUI
import SwiftBSON

// MARK: - DocumentJSONView

struct DocumentJSONView: View {
    let documents: [BSONDocument]
    let timeZone: TimeZone
    let isLoading: Bool
    let onSave: ((_ original: BSONDocument, _ replacement: BSONDocument) async -> Bool)?
    let onEdit: ((BSONDocument) -> Void)?
    let onDelete: (([BSONDocument]) -> Void)?

    @State private var editingDocumentID: String? = nil

    init(
        documents: [BSONDocument],
        timeZone: TimeZone,
        isLoading: Bool,
        onSave: ((_ original: BSONDocument, _ replacement: BSONDocument) async -> Bool)? = nil,
        onEdit: ((BSONDocument) -> Void)? = nil,
        onDelete: (([BSONDocument]) -> Void)? = nil
    ) {
        self.documents = documents
        self.timeZone = timeZone
        self.isLoading = isLoading
        self.onSave = onSave
        self.onEdit = onEdit
        self.onDelete = onDelete
    }

    var body: some View {
        if isLoading && documents.isEmpty {
            VStack(spacing: 12) {
                ProgressView()
                    .controlSize(.regular)
                Text("Loading...")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if documents.isEmpty {
            VStack {
                ContentUnavailableView(
                    "No documents",
                    systemImage: "curlybraces",
                    description: Text("This collection is empty or the filter returned no results.")
                )
                .padding(.top, 40)
                Spacer()
            }
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(documents.indices, id: \.self) { index in
                        let doc = documents[index]
                        let itemWrapper = wrapper(for: doc, index: index)
                        JSONDocumentCard(
                            wrapper: itemWrapper,
                            isEditing: editingDocumentID == itemWrapper.id,
                            onRequestEdit: onSave != nil ? {
                                editingDocumentID = itemWrapper.id
                            } : nil,
                            onCancelEdit: {
                                if editingDocumentID == itemWrapper.id {
                                    editingDocumentID = nil
                                }
                            },
                            onSave: { updatedDoc in
                                guard let onSave else { return false }
                                let success = await onSave(doc, updatedDoc)
                                if success {
                                    editingDocumentID = nil
                                }
                                return success
                            },
                            onDelete: onDelete != nil ? { targetDoc in
                                onDelete?([targetDoc])
                            } : nil
                        )
                    }
                }
                .padding(16)
            }
            .overlay {
                if isLoading {
                    VStack {
                        ProgressView()
                            .controlSize(.regular)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.ultraThinMaterial.opacity(0.3))
                }
            }
        }
    }

    private func wrapper(for document: BSONDocument, index: Int) -> JSONDocumentWrapper {
        let id = JSONNode.rootID(for: document)
        return JSONDocumentWrapper(
            id: id,
            index: index,
            document: document,
            timeZone: timeZone
        )
    }
}

// MARK: - JSONDocumentCard

struct JSONDocumentCard: View {
    let wrapper: JSONDocumentWrapper
    var isEditing: Bool = false
    var onRequestEdit: (() -> Void)? = nil
    var onCancelEdit: (() -> Void)? = nil
    var onSave: ((BSONDocument) async -> Bool)? = nil
    var onDelete: ((BSONDocument) -> Void)? = nil

    @State private var expandedPaths: Set<String> = []
    @State private var isHovered: Bool = false

    var body: some View {
        Group {
            if isEditing {
                EditableDocumentOutlineView(
                    originalDocument: wrapper.document,
                    timeZone: wrapper.timeZone,
                    onSave: { updatedDoc in
                        if let onSave {
                            return await onSave(updatedDoc)
                        }
                        return false
                    },
                    onCancel: {
                        onCancelEdit?()
                    }
                )
            } else {
                textViewCard
            }
        }
    }

    private var textViewCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(currentAttributedText)
                .font(.system(.callout, design: .monospaced))
                .textSelection(.enabled)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .environment(\.openURL, OpenURLAction { url in
                    guard url.scheme == "mongofold" else { return .systemAction }
                    let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
                    guard let path = components?.queryItems?.first(where: { $0.name == "path" })?.value, !path.isEmpty else {
                        return .handled
                    }
                    if expandedPaths.contains(path) {
                        expandedPaths.remove(path)
                    } else {
                        expandedPaths.insert(path)
                    }
                    return .handled
                })
        }
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.regularMaterial)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.primary.opacity(0.07), lineWidth: 1)
        )
        .overlay(alignment: .topTrailing) {
            if onRequestEdit != nil || onDelete != nil {
                actionButtons
                    .opacity(isHovered ? 1 : 0)
                    .animation(.easeInOut(duration: 0.15), value: isHovered)
                    .padding(8)
            }
        }
        .onHover { hovering in
            isHovered = hovering
        }
    }

    private var actionButtons: some View {
        HStack(spacing: 4) {
            if let onRequestEdit {
                Button(action: onRequestEdit) {
                    Image(systemName: "pencil")
                        .font(.system(size: 11, weight: .semibold))
                        .frame(width: 24, height: 24)
                        .foregroundStyle(.primary)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Edit document (Outline Tree)")
            }

            if let onDelete {
                Button(action: {
                    onDelete(wrapper.document)
                }) {
                    Image(systemName: "trash")
                        .font(.system(size: 11, weight: .semibold))
                        .frame(width: 24, height: 24)
                        .foregroundStyle(.red.opacity(0.85))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Delete document")
            }
        }
        .padding(3)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(Color.primary.opacity(0.12), lineWidth: 0.8)
        )
        .shadow(color: .black.opacity(0.1), radius: 3, x: 0, y: 1)
    }

    private var currentAttributedText: AttributedString {
        if expandedPaths.isEmpty {
            return wrapper.attributedText
        }
        return BSONAttributedStringFormatter(
            timeZone: wrapper.timeZone,
            expandedPaths: expandedPaths
        ).format(document: wrapper.document)
    }
}

struct JSONDocumentCardContainer: View {
    let wrapper: JSONDocumentWrapper

    var body: some View {
        JSONDocumentCard(wrapper: wrapper)
    }
}
