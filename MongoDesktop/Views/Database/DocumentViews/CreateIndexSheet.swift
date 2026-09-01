import SwiftUI
import SwiftBSON

// MARK: - Index Field Configuration

struct IndexFieldItem: Identifiable, Equatable {
    let id = UUID()
    var fieldName: String = ""
    var indexType: IndexFieldType = .ascending
}

enum IndexFieldType: String, CaseIterable, Identifiable {
    case ascending = "1 (Ascending)"
    case descending = "-1 (Descending)"
    case text = "Text"
    case geospatial2dsphere = "2dsphere"
    case geospatial2d = "2d"
    case hashed = "Hashed"

    var id: String { rawValue }

    var bsonValue: BSON {
        switch self {
        case .ascending: return .int32(1)
        case .descending: return .int32(-1)
        case .text: return .string("text")
        case .geospatial2dsphere: return .string("2dsphere")
        case .geospatial2d: return .string("2d")
        case .hashed: return .string("hashed")
        }
    }

    var suffix: String {
        switch self {
        case .ascending: return "1"
        case .descending: return "-1"
        case .text: return "text"
        case .geospatial2dsphere: return "2dsphere"
        case .geospatial2d: return "2d"
        case .hashed: return "hashed"
        }
    }
}

// MARK: - CreateIndexSheet

struct CreateIndexSheet: View {
    let database: String
    let collection: String
    let documentKeys: [String]
    @Binding var isPresented: Bool

    @EnvironmentObject private var indexVM: IndexQueryViewModel
    @EnvironmentObject private var sessionViewModel: DatabaseSessionViewModel

    @State private var fields: [IndexFieldItem] = [IndexFieldItem()]
    @State private var customIndexName: String = ""
    @State private var isUnique: Bool = false
    @State private var isSparse: Bool = false
    @State private var useTTL: Bool = false
    @State private var ttlSeconds: Int = 3600
    @State private var showAdvancedOptions: Bool = false
    @State private var usePartialFilter: Bool = false
    @State private var partialFilterText: String = "{\n  \n}"
    @State private var partialFilterError: String? = nil
    @State private var buildInBackground: Bool = false

    @State private var isCreating: Bool = false
    @State private var errorMessage: String? = nil

    private var defaultIndexName: String {
        let validFields = fields.filter { !$0.fieldName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        if validFields.isEmpty { return "index_name" }
        return validFields.map { "\($0.fieldName.trimmingCharacters(in: .whitespacesAndNewlines))_\($0.indexType.suffix)" }.joined(separator: "_")
    }

    private var hasValidFields: Bool {
        let validFields = fields.filter { !$0.fieldName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        return !validFields.isEmpty
    }

    private var isFormValid: Bool {
        guard hasValidFields else { return false }
        if useTTL && ttlSeconds < 0 { return false }
        if usePartialFilter && partialFilterError != nil { return false }
        return true
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView

            Divider()

            // Scrollable Content
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if let error = errorMessage {
                        errorBanner(error)
                    }

                    // Fields Configuration Section
                    fieldsSection

                    // General Options Section
                    optionsSection

                    // Advanced Options Section
                    advancedSection

                    // Command Preview Section
                    previewSection
                }
                .padding(24)
            }

            Divider()

            // Footer Actions
            footerView
        }
        .frame(width: 620, height: 600)
    }

    // MARK: - Header View

    private var headerView: some View {
        HStack(alignment: .center) {
            Image(systemName: "plus.square.fill")
                .font(.title2)
                .foregroundStyle(Color.accentColor)

            VStack(alignment: .leading, spacing: 2) {
                Text("Create Index")
                    .font(.title3.bold())

                Text("\(database).\(collection)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button(action: { isPresented = false }) {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.secondary)
                    .padding(6)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .background(.ultraThinMaterial)
    }

    // MARK: - Error Banner

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.red)
                .font(.system(size: 14))

            Text(message)
                .font(.caption)
                .foregroundColor(.red)
                .multilineTextAlignment(.leading)

            Spacer()

            Button(action: { errorMessage = nil }) {
                Image(systemName: "xmark")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(10)
        .background(Color.red.opacity(0.1))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.red.opacity(0.3), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    // MARK: - Fields Section

    private var fieldsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Index Fields", systemImage: "key.fill")
                    .font(.subheadline.weight(.semibold))

                Spacer()

                Button(action: addField) {
                    Label("Add Field", systemImage: "plus")
                        .font(.caption.weight(.medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            VStack(spacing: 8) {
                ForEach(fields.indices, id: \.self) { index in
                    HStack(spacing: 8) {
                        // Field Name Text Input with autocomplete suggestions
                        HStack(spacing: 4) {
                            TextField("Field name (e.g. email, createdAt)", text: $fields[index].fieldName)
                                .textFieldStyle(.plain)
                                .font(.system(.body, design: .monospaced))

                            if !documentKeys.isEmpty {
                                Menu {
                                    ForEach(documentKeys, id: \.self) { key in
                                        Button(key) {
                                            fields[index].fieldName = key
                                        }
                                    }
                                } label: {
                                    Image(systemName: "chevron.down.circle.fill")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                .menuStyle(.borderlessButton)
                                .fixedSize()
                            }
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(Color.primary.opacity(0.04))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 6))

                        // Index Type Picker
                        Picker("", selection: $fields[index].indexType) {
                            ForEach(IndexFieldType.allCases) { type in
                                Text(type.rawValue).tag(type)
                            }
                        }
                        .frame(width: 175)

                        // Remove Field Button
                        if fields.count > 1 {
                            Button(action: { removeField(at: index) }) {
                                Image(systemName: "trash")
                                    .font(.caption)
                                    .foregroundColor(.red.opacity(0.8))
                                    .padding(6)
                            }
                            .buttonStyle(.plain)
                            .help("Remove Field")
                        }
                    }
                }
            }
        }
    }

    // MARK: - Options Section

    private var optionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Index Options", systemImage: "slider.horizontal.3")
                .font(.subheadline.weight(.semibold))

            // Custom Index Name
            VStack(alignment: .leading, spacing: 4) {
                Text("Index Name (Optional)")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)

                TextField(defaultIndexName, text: $customIndexName)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
            }

            VStack(alignment: .leading, spacing: 10) {
                // Unique Index Toggle
                Toggle(isOn: $isUnique) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Unique Index")
                            .font(.body.weight(.medium))
                        Text("Rejects documents with duplicate values for the index key.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.checkbox)

                // Sparse Index Toggle
                Toggle(isOn: $isSparse) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Sparse Index")
                            .font(.body.weight(.medium))
                        Text("Only index documents that contain the indexed fields.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.checkbox)

                // TTL Toggle
                Toggle(isOn: $useTTL) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("TTL (Time to Live) Expiration")
                            .font(.body.weight(.medium))
                        Text("Automatically remove documents after a specified number of seconds.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.checkbox)

                if useTTL {
                    HStack(spacing: 8) {
                        Text("Expire after:")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        TextField("Seconds", value: $ttlSeconds, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 100)
                            .font(.system(.body, design: .monospaced))

                        Text("seconds")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Text("(\(formatDuration(seconds: ttlSeconds)))")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(Color.accentColor)
                    }
                    .padding(.leading, 24)
                }
            }
        }
    }

    // MARK: - Advanced Section

    private var advancedSection: some View {
        DisclosureGroup(isExpanded: $showAdvancedOptions) {
            VStack(alignment: .leading, spacing: 12) {
                // Partial Filter Expression Toggle & Editor
                Toggle(isOn: $usePartialFilter) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Partial Filter Expression")
                            .font(.body.weight(.medium))
                        Text("Only index documents that meet the specified filter criteria.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.checkbox)

                if usePartialFilter {
                    VStack(alignment: .leading, spacing: 4) {
                        JSONEditorView(
                            text: $partialFilterText,
                            errorMessage: $partialFilterError,
                            documentKeys: documentKeys,
                            minHeight: 80
                        )
                        .frame(height: 90)
                        .overlay {
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(partialFilterError == nil ? Color.secondary.opacity(0.3) : Color.red.opacity(0.7), lineWidth: 1)
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 6))

                        if let error = partialFilterError {
                            Text(error)
                                .font(.caption2)
                                .foregroundStyle(.red)
                        }
                    }
                    .padding(.leading, 24)
                }

                // Background build
                Toggle(isOn: $buildInBackground) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Build in Background")
                            .font(.body.weight(.medium))
                        Text("Build index in the background to avoid blocking other operations (MongoDB < 4.2).")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.checkbox)
            }
            .padding(.top, 8)
        } label: {
            Label("Advanced Options", systemImage: "gearshape")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Command Preview Section

    private var previewSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("MongoDB Command Preview")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            ScrollView(.horizontal, showsIndicators: false) {
                Text(previewCommandString)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.primary)
                    .padding(10)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.primary.opacity(0.03))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
    }

    // MARK: - Footer View

    private var footerView: some View {
        HStack(spacing: 12) {
            Spacer()

            Button("Cancel") {
                isPresented = false
            }
            .buttonStyle(.bordered)
            .keyboardShortcut(.escape, modifiers: [])
            .disabled(isCreating)

            Button(action: createIndex) {
                HStack(spacing: 6) {
                    if isCreating {
                        ProgressView()
                            .controlSize(.small)
                    }
                    Text("Create Index")
                        .fontWeight(.semibold)
                }
                .padding(.horizontal, 6)
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.return, modifiers: [])
            .disabled(!isFormValid || isCreating)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .background(.ultraThinMaterial)
    }

    // MARK: - Actions & Helpers

    private func addField() {
        fields.append(IndexFieldItem())
    }

    private func removeField(at index: Int) {
        guard fields.count > 1 else { return }
        fields.remove(at: index)
    }

    private func buildKeyDocument() -> BSONDocument {
        var keyDoc = BSONDocument()
        for item in fields {
            let trimmed = item.fieldName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            keyDoc[trimmed] = item.indexType.bsonValue
        }
        return keyDoc
    }

    private func buildOptionsDocument() -> BSONDocument {
        var options = BSONDocument()

        let trimmedName = customIndexName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedName.isEmpty {
            options["name"] = .string(trimmedName)
        }

        if isUnique {
            options["unique"] = .bool(true)
        }
        if isSparse {
            options["sparse"] = .bool(true)
        }
        if useTTL && ttlSeconds >= 0 {
            options["expireAfterSeconds"] = .int32(Int32(ttlSeconds))
        }
        if usePartialFilter,
           let partialDoc = try? MongoQueryParsing.parseFilter(partialFilterText),
           !partialDoc.isEmpty {
            options["partialFilterExpression"] = .document(partialDoc)
        }
        if buildInBackground {
            options["background"] = .bool(true)
        }

        return options
    }

    private var previewCommandString: String {
        let keyDoc = buildKeyDocument()
        let optionsDoc = buildOptionsDocument()

        let keyJson = keyDoc.isEmpty ? "{ ... }" : keyDoc.toExtendedJSONString()
        if optionsDoc.isEmpty {
            return "db.\(collection).createIndex(\(keyJson))"
        } else {
            return "db.\(collection).createIndex(\(keyJson), \(optionsDoc.toExtendedJSONString()))"
        }
    }

    private func createIndex() {
        guard isFormValid else { return }
        isCreating = true
        errorMessage = nil

        let keyDoc = buildKeyDocument()
        let optionsDoc = buildOptionsDocument()

        Task {
            do {
                try await indexVM.createIndex(
                    database: database,
                    collection: collection,
                    keys: keyDoc,
                    options: optionsDoc,
                    session: sessionViewModel
                )
                isCreating = false
                isPresented = false
            } catch {
                isCreating = false
                errorMessage = error.localizedDescription
            }
        }
    }

    private func formatDuration(seconds: Int) -> String {
        if seconds < 60 {
            return "\(seconds)s"
        } else if seconds < 3600 {
            let minutes = seconds / 60
            let remainder = seconds % 60
            return remainder > 0 ? "\(minutes)m \(remainder)s" : "\(minutes)m"
        } else if seconds < 86400 {
            let hours = seconds / 3600
            let minutes = (seconds % 3600) / 60
            return minutes > 0 ? "\(hours)h \(minutes)m" : "\(hours)h"
        } else {
            let days = seconds / 86400
            let hours = (seconds % 86400) / 3600
            return hours > 0 ? "\(days)d \(hours)h" : "\(days)d"
        }
    }
}
