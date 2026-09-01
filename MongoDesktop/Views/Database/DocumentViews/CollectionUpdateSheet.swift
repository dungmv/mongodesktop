import SwiftUI
import SwiftBSON

struct CollectionUpdateSheet: View {
    let database: String
    let collection: String
    let filterText: String
    let sampleDocuments: [BSONDocument]
    let totalCount: Int
    let documentKeys: [String]
    @Binding var isPresented: Bool
    var onUpdate: (BSONDocument, BSONDocument) async -> Void

    @State private var updateText: String = "{\n  \"$set\": {\n    \n  }\n}"
    @State private var updateError: String? = nil
    @State private var isUpdating: Bool = false
    @State private var showInfoPopover: Bool = false

    init(
        database: String,
        collection: String,
        filterText: String,
        existingDocuments: [BSONDocument],
        totalCount: Int,
        documentKeys: [String],
        isPresented: Binding<Bool>,
        onUpdate: @escaping (BSONDocument, BSONDocument) async -> Void
    ) {
        self.database = database
        self.collection = collection
        self.filterText = filterText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "{}" : filterText
        self.sampleDocuments = Array(existingDocuments.prefix(3))
        self.totalCount = totalCount > 0 ? totalCount : existingDocuments.count
        self.documentKeys = documentKeys
        self._isPresented = isPresented
        self.onUpdate = onUpdate
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Update \(totalCount) documents")
                        .font(.title2.bold())

                    Text("\(database).\(collection)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button(action: { isPresented = false }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.secondary)
                        .padding(6)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)
            .padding(.bottom, 16)

            // Main Content Area
            HStack(alignment: .top, spacing: 20) {
                // Left Column: Filter (Read-Only) & Update Editor
                VStack(alignment: .leading, spacing: 16) {
                    // Filter Section (Non-editable)
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 6) {
                            Text("Filter")
                                .font(.subheadline.weight(.semibold))

                            Button(action: { showInfoPopover.toggle() }) {
                                Image(systemName: "info.circle.fill")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .popover(isPresented: $showInfoPopover) {
                                Text("Matches documents to update using current query filter.")
                                    .font(.caption)
                                    .padding(10)
                                    .frame(maxWidth: 240)
                            }
                        }

                        Text(filterText)
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(.primary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .frame(minHeight: 36)
                            .background(Color.primary.opacity(0.04))
                            .overlay(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    }

                    // Update Section
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Update")
                                .font(.subheadline.weight(.semibold))

                            Spacer()

                            if let url = URL(string: "https://www.mongodb.com/docs/manual/reference/operator/update/") {
                                Link(destination: url) {
                                    HStack(spacing: 3) {
                                        Text("Learn more about Update syntax")
                                        Image(systemName: "arrow.up.right.square")
                                    }
                                    .font(.caption)
                                    .foregroundStyle(Color.accentColor)
                                }
                            }
                        }

                        JSONEditorView(
                            text: $updateText,
                            errorMessage: $updateError,
                            documentKeys: documentKeys,
                            minHeight: 160
                        )
                        .frame(height: 180)
                        .overlay {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .stroke(updateError == nil ? Color.secondary.opacity(0.3) : Color.red.opacity(0.7), lineWidth: 1)
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

                        if let error = updateError {
                            Text(error)
                                .font(.caption2)
                                .foregroundStyle(.red)
                        }
                    }
                }
                .frame(width: 400)

                // Right Column: Live Preview using loaded output documents
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 4) {
                        Text("Preview")
                            .font(.subheadline.weight(.semibold))
                        Text("(sample of \(sampleDocuments.count) documents)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    VStack(spacing: 0) {
                        if sampleDocuments.isEmpty {
                            VStack(spacing: 8) {
                                Image(systemName: "doc.text.magnifyingglass")
                                    .font(.largeTitle)
                                    .foregroundStyle(.tertiary)
                                Text("No loaded documents available for preview")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        } else {
                            ScrollView {
                                LazyVStack(alignment: .leading, spacing: 10) {
                                    ForEach(sampleDocuments.indices, id: \.self) { idx in
                                        let originalDoc = sampleDocuments[idx]
                                        let updatedDoc = previewUpdatedDocument(originalDoc)
                                        JSONDocumentCardContainer(
                                            wrapper: wrapper(for: updatedDoc, index: idx)
                                        )
                                    }
                                }
                                .padding(12)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.primary.opacity(0.02))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding(.horizontal, 24)

            Spacer(minLength: 16)

            Divider()

            // Footer
            HStack(spacing: 12) {
                Spacer()

                Button(action: { isPresented = false }) {
                    Text("Cancel")
                        .font(.body.weight(.semibold))
                        .foregroundColor(.primary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(
                            Color.primary.opacity(0.06),
                            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.escape, modifiers: [])

                Button(action: performUpdate) {
                    HStack(spacing: 6) {
                        if isUpdating {
                            ProgressView()
                                .controlSize(.small)
                        }
                        Text("Update \(totalCount) documents")
                            .font(.body.weight(.semibold))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(
                        updateError != nil || isUpdating
                            ? Color.gray.opacity(0.5)
                            : Color(red: 0.0, green: 0.41, blue: 0.28), // MongoDB Deep Green (#00684A)
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                    )
                }
                .buttonStyle(.plain)
                .disabled(updateError != nil || isUpdating)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
            .background(.ultraThinMaterial)
        }
        .frame(width: 860, height: 480)
    }

    // MARK: - Preview Logic

    private func previewUpdatedDocument(_ original: BSONDocument) -> BSONDocument {
        guard let updateDoc = try? MongoQueryParsing.parseQueryOption(updateText) else {
            return original
        }

        var doc = original

        // $set
        if case .document(let setDoc)? = updateDoc["$set"] {
            for (k, v) in setDoc {
                doc[k] = v
            }
        }
        // $unset
        if case .document(let unsetDoc)? = updateDoc["$unset"] {
            for (k, _) in unsetDoc {
                doc[k] = nil
            }
        }
        // $inc
        if case .document(let incDoc)? = updateDoc["$inc"] {
            for (k, v) in incDoc {
                if let existing = doc[k] {
                    switch (existing, v) {
                    case (.int32(let a), .int32(let b)): doc[k] = .int32(a + b)
                    case (.int64(let a), .int64(let b)): doc[k] = .int64(a + b)
                    case (.double(let a), .double(let b)): doc[k] = .double(a + b)
                    default: break
                    }
                }
            }
        }
        // $rename
        if case .document(let renameDoc)? = updateDoc["$rename"] {
            for (oldK, newKVal) in renameDoc {
                if case .string(let newK) = newKVal, let existing = doc[oldK] {
                    doc[oldK] = nil
                    doc[newK] = existing
                }
            }
        }

        // Direct key replacement if no operators
        let hasOperators = updateDoc.keys.contains { $0.hasPrefix("$") }
        if !hasOperators {
            for (k, v) in updateDoc {
                if k != "_id" {
                    doc[k] = v
                }
            }
        }

        return doc
    }

    private func wrapper(for document: BSONDocument, index: Int) -> JSONDocumentWrapper {
        let id = JSONNode.rootID(for: document)
        return JSONDocumentWrapper(
            id: id,
            index: index,
            document: document,
            timeZone: TimeZone.current
        )
    }

    private func performUpdate() {
        guard updateError == nil else { return }
        isUpdating = true

        Task {
            do {
                let parsedFilter = try MongoQueryParsing.parseFilter(filterText)
                guard let parsedUpdate = try MongoQueryParsing.parseQueryOption(updateText) else {
                    isUpdating = false
                    return
                }

                await onUpdate(parsedFilter, parsedUpdate)
                isUpdating = false
                isPresented = false
            } catch {
                isUpdating = false
            }
        }
    }
}
