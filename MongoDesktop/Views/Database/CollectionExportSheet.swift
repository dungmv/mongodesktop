import SwiftUI
import SwiftBSON

struct CollectionExportSheet: View {
    let database: String
    let collection: String
    let defaultFilter: String
    let defaultSort: String
    let defaultProjection: String
    let documentKeys: [String]
    
    @Binding var isPresented: Bool
    
    @State private var filterText = "{}"
    @State private var sortText = "{}"
    @State private var projectionText = "{}"
    
    @State private var filterError: String? = nil
    @State private var sortError: String? = nil
    @State private var projectionError: String? = nil
    
    @State private var format: ExportFormat = .jsonArray
    
    @State private var estimatedCount: Int? = nil
    @State private var isEstimating = false
    @State private var estimationError: String? = nil
    
    @State private var isExporting = false
    @State private var exportedCount = 0
    @State private var totalToExport = 0
    @State private var exportError: String? = nil
    @State private var exportSuccess = false
    
    @State private var currentExportTask: Task<Void, Never>? = nil
    
    private let mongoService = MongoService.shared
    
    init(
        database: String,
        collection: String,
        defaultFilter: String,
        defaultSort: String,
        defaultProjection: String,
        documentKeys: [String],
        isPresented: Binding<Bool>
    ) {
        self.database = database
        self.collection = collection
        self.defaultFilter = defaultFilter
        self.defaultSort = defaultSort
        self.defaultProjection = defaultProjection
        self.documentKeys = documentKeys
        self._isPresented = isPresented
        
        self._filterText = State(initialValue: defaultFilter)
        self._sortText = State(initialValue: defaultSort)
        self._projectionText = State(initialValue: defaultProjection)
    }
    
    private var hasSyntaxError: Bool {
        filterError != nil || sortError != nil || projectionError != nil
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "square.and.arrow.up")
                    .font(.title2)
                    .foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Export Collection")
                        .font(.headline)
                    Text("\(database).\(collection)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(.ultraThinMaterial)
            
            Divider()
            
            // Content
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Export Format Picker
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Export Format")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        
                        Picker("", selection: $format) {
                            ForEach(ExportFormat.allCases) { fmt in
                                Text(fmt.rawValue).tag(fmt)
                            }
                        }
                        .pickerStyle(.segmented)
                        
                        Text(format == .jsonArray ? 
                             "Standard JSON array containing all documents as list elements." : 
                             "High-performance Line-delimited JSON (NDJSON), one JSON object per line.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .padding(.top, 2)
                    }
                    
                    // Filter Query
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Filter Query")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        
                        JSONEditorView(
                            text: $filterText,
                            errorMessage: $filterError,
                            documentKeys: documentKeys,
                            minHeight: 80
                        )
                        .frame(height: 80)
                        .overlay {
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(filterError == nil ? Color.secondary.opacity(0.3) : .red.opacity(0.6), lineWidth: 1)
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        
                        if let error = filterError {
                            Text(error)
                                .font(.caption2)
                                .foregroundStyle(.red)
                        }
                    }
                    
                    // Sort Query
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Sort (Optional)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        
                        JSONEditorView(
                            text: $sortText,
                            errorMessage: $sortError,
                            documentKeys: documentKeys,
                            minHeight: 40
                        )
                        .frame(height: 40)
                        .overlay {
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(sortError == nil ? Color.secondary.opacity(0.3) : .red.opacity(0.6), lineWidth: 1)
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        
                        if let error = sortError {
                            Text(error)
                                .font(.caption2)
                                .foregroundStyle(.red)
                        }
                    }
                    
                    // Projection Query
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Projection (Optional)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        
                        JSONEditorView(
                            text: $projectionText,
                            errorMessage: $projectionError,
                            documentKeys: documentKeys,
                            minHeight: 40
                        )
                        .frame(height: 40)
                        .overlay {
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(projectionError == nil ? Color.secondary.opacity(0.3) : .red.opacity(0.6), lineWidth: 1)
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        
                        if let error = projectionError {
                            Text(error)
                                .font(.caption2)
                                .foregroundStyle(.red)
                        }
                    }
                    
                    // Estimate & Status Panel
                    HStack {
                        if isEstimating {
                            ProgressView()
                                .controlSize(.small)
                                .padding(.trailing, 4)
                            Text("Calculating estimate...")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        } else if let error = estimationError {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.red)
                            Text("Invalid query: \(error)")
                                .font(.subheadline)
                                .foregroundStyle(.red)
                                .lineLimit(2)
                        } else if let count = estimatedCount {
                            Image(systemName: "chart.bar.doc.horizontal.fill")
                                .foregroundStyle(.secondary)
                            HStack(spacing: 0) {
                                Text("Estimated documents to export: ")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                Text("\(count)")
                                    .font(.subheadline.bold())
                                    .foregroundStyle(.primary)
                            }
                        }
                        Spacer()
                    }
                    .padding(10)
                    .background(Color.secondary.opacity(0.08))
                    .cornerRadius(6)
                }
                .padding(20)
            }
            
            Divider()
            
            // Footer
            VStack(spacing: 0) {
                if isExporting {
                    VStack(spacing: 8) {
                        HStack {
                            Text("Exporting documents...")
                                .font(.subheadline.bold())
                            Spacer()
                            Text("\(exportedCount) / \(totalToExport)")
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                        }
                        
                        ProgressView(value: Double(exportedCount), total: Double(max(1, totalToExport)))
                            .progressViewStyle(.linear)
                        
                        Button("Cancel Export") {
                            cancelExport()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                } else {
                    HStack {
                        if exportSuccess {
                            HStack(spacing: 6) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                                Text("Exported \(exportedCount) documents successfully!")
                                    .font(.subheadline)
                                    .foregroundStyle(.green)
                            }
                            Spacer()
                        } else if let err = exportError {
                            HStack(spacing: 6) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.red)
                                Text(err)
                                    .font(.subheadline)
                                    .foregroundStyle(.red)
                                    .lineLimit(2)
                            }
                            Spacer()
                        }
                        
                        Spacer()
                        
                        Button("Cancel") {
                            isPresented = false
                        }
                        .buttonStyle(.bordered)
                        .keyboardShortcut(.escape, modifiers: [])
                        
                        Button("Export...") {
                            startExport()
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(hasSyntaxError || isEstimating || estimatedCount == 0)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                    .background(.ultraThinMaterial)
                }
            }
        }
        .frame(width: 520, height: 500)
        .task(id: filterText) {
            do {
                try await Task.sleep(nanoseconds: 500_000_000)
            } catch {
                return
            }
            await updateEstimate()
        }
    }
    
    private func updateEstimate() async {
        let trimmed = filterText.trimmingCharacters(in: .whitespacesAndNewlines)
        
        isEstimating = true
        estimationError = nil
        
        do {
            let parsedFilter = try MongoQueryParsing.parseFilter(trimmed)
            let count = try await mongoService.countDocuments(
                database: database,
                collection: collection,
                filter: parsedFilter
            )
            self.estimatedCount = count
            self.estimationError = nil
        } catch {
            self.estimationError = error.localizedDescription
            self.estimatedCount = nil
        }
        isEstimating = false
    }
    
    private func startExport() {
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.json]
        savePanel.canCreateDirectories = true
        savePanel.isExtensionHidden = false
        savePanel.title = "Export Collection"
        savePanel.nameFieldStringValue = "\(collection).json"
        
        guard savePanel.runModal() == .OK, let fileURL = savePanel.url else {
            return
        }
        
        isExporting = true
        exportError = nil
        exportSuccess = false
        exportedCount = 0
        totalToExport = estimatedCount ?? 0
        
        let task = Task {
            do {
                let parsedFilter = try MongoQueryParsing.parseFilter(filterText)
                let parsedSort = try MongoQueryParsing.parseQueryOption(sortText)
                let parsedProjection = try MongoQueryParsing.parseQueryOption(projectionText)
                
                try await mongoService.exportCollection(
                    database: database,
                    collection: collection,
                    filter: parsedFilter,
                    sort: parsedSort,
                    projection: parsedProjection,
                    to: fileURL,
                    format: format
                ) { progress in
                    Task { @MainActor in
                        self.exportedCount = progress
                    }
                }
                
                Task { @MainActor in
                    self.isExporting = false
                    self.exportSuccess = true
                }
            } catch {
                Task { @MainActor in
                    self.isExporting = false
                    self.exportError = error.localizedDescription
                }
            }
        }
        
        currentExportTask = task
    }
    
    private func cancelExport() {
        currentExportTask?.cancel()
        currentExportTask = nil
        isExporting = false
        exportError = "Export cancelled by user."
    }
}
