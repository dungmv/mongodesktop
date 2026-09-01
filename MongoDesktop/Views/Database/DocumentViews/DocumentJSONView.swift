import SwiftUI
import SwiftBSON

// MARK: - DocumentJSONView

struct DocumentJSONView: View {
    let documents: [BSONDocument]
    let timeZone: TimeZone
    let isLoading: Bool
    let onEdit: (BSONDocument) -> Void
    let onDelete: ([BSONDocument]) -> Void

    init(
        documents: [BSONDocument],
        timeZone: TimeZone,
        isLoading: Bool,
        onEdit: @escaping (BSONDocument) -> Void = { _ in },
        onDelete: @escaping ([BSONDocument]) -> Void = { _ in }
    ) {
        self.documents = documents
        self.timeZone = timeZone
        self.isLoading = isLoading
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
                        JSONDocumentCard(
                            wrapper: wrapper(for: documents[index], index: index),
                            onEdit: onEdit,
                            onDelete: { doc in onDelete([doc]) }
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
    var onEdit: ((BSONDocument) -> Void)? = nil
    var onDelete: ((BSONDocument) -> Void)? = nil
    @State private var expandedPaths: Set<String> = []

    var body: some View {
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
