import SwiftUI
import SwiftBSON

struct DatabaseDetailView: View {
    var connection: Connection
    var databaseName: String
    
    @State private var collections: [String] = []
    @State private var isLoading = true
    @State private var errorMessage: String? = nil
    @State private var selectedCollection: String? = nil
    
    var body: some View {
        HSplitView {
            List(selection: $selectedCollection) {
                if isLoading {
                    ProgressView("Loading collections...")
                } else if let error = errorMessage {
                    Text(error)
                        .foregroundColor(.red)
                } else if collections.isEmpty {
                    Text("No collections found")
                        .foregroundColor(.secondary)
                } else {
                    ForEach(collections, id: \.self) { collection in
                        Text(collection)
                            .tag(collection)
                    }
                }
            }
            .frame(minWidth: 200)
            .task {
                await loadCollections()
            }
            .refreshable {
                await loadCollections()
            }
            
            if let collection = selectedCollection {
                DocumentsView(connection: connection, databaseName: databaseName, collectionName: collection)
            } else {
                Text("Select a Collection")
                    .foregroundColor(.secondary)
            }
        }
        .navigationTitle(databaseName)
    }
    
    private func loadCollections() async {
        isLoading = true
        errorMessage = nil
        
        do {
            collections = try await MongoDBService.shared.listCollections(in: databaseName, for: connection)
        } catch {
            errorMessage = "Failed to load collections: \(error.localizedDescription)"
        }
        
        isLoading = false
    }
}

struct DocumentsView: View {
    var connection: Connection
    var databaseName: String
    var collectionName: String
    
    @State private var documents: [BSONDocument] = []
    @State private var isLoading = true
    @State private var errorMessage: String? = nil
    @State private var documentCount: Int = 0
    @State private var currentPage = 0
    @State private var pageSize = 20
    
    var body: some View {
        VStack {
            if isLoading && documents.isEmpty {
                ProgressView("Loading documents...")
            } else if let error = errorMessage {
                Text(error)
                    .foregroundColor(.red)
                    .padding()
            } else if documents.isEmpty {
                Text("No Documents")
                    .foregroundColor(.secondary)
            } else {
                List {
                    ForEach(0..<documents.count, id: \.self) { index in
                        let document = documents[index]
                        DocumentRowView(document: document)
                    }
                }
                
                if documentCount > pageSize {
                    HStack {
                        Button(action: { if currentPage > 0 { currentPage -= 1; Task { await loadDocuments() } } }) {
                            Text("Previous")
                        }
                        .disabled(currentPage == 0)
                        
                        Text("Page \(currentPage + 1) of \(Int(ceil(Double(documentCount) / Double(pageSize))))")
                        
                        Button(action: { if (currentPage + 1) * pageSize < documentCount { currentPage += 1; Task { await loadDocuments() } } }) {
                            Text("Next")
                        }
                        .disabled((currentPage + 1) * pageSize >= documentCount)
                    }
                    .padding()
                }
            }
        }
        .navigationTitle(collectionName)
        .task {
            await loadDocumentCount()
            await loadDocuments()
        }
        .refreshable {
            await loadDocumentCount()
            await loadDocuments()
        }
    }
    
    private func loadDocumentCount() async {
        do {
            documentCount = try await MongoDBService.shared.countDocuments(in: collectionName, database: databaseName, for: connection)
        } catch {
            errorMessage = "Failed to load document count: \(error.localizedDescription)"
        }
    }
    
    private func loadDocuments() async {
        isLoading = true
        errorMessage = nil
        
        do {
            documents = try await MongoDBService.shared.findDocuments(
                in: collectionName,
                database: databaseName,
                for: connection,
                limit: pageSize,
                skip: currentPage * pageSize
            )
        } catch {
            errorMessage = "Failed to load documents: \(error.localizedDescription)"
        }
        
        isLoading = false
    }
}

struct DocumentRowView: View {
    var document: BSONDocument
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let id = document["_id"] {
                Text("ID: \(String(describing: id))")
                    .font(.headline)
            }
            
            ForEach(Array(document.keys.prefix(3).filter { $0 != "_id" }), id: \.self) { key in
                if let value = document[key] {
                    Text("\(key): \(String(describing: value))")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.vertical, 4)
    }
}
