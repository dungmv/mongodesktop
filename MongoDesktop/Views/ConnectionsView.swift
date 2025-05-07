//
//  ConnectionsView.swift
//  mongoui
//
//  Created by Trae AI on 21/4/25.
//

import SwiftUI
import SwiftData

struct ConnectionsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var connections: [Connection]
    @State private var showingAddConnection = false
    @State private var showingConnectionsList = false
    @State private var selectedConnection: Connection?
    
    var body: some View {
        NavigationStack {
            VStack {
                if let connection = selectedConnection {
                    DatabaseView(connection: connection)
                } else {
                    ContentUnavailableView("Chưa chọn kết nối", systemImage: "network", description: Text("Vui lòng chọn một kết nối MongoDB để bắt đầu"))
                }
            }
            .navigationTitle("MongoDB Desktop")
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    Button(action: { showingConnectionsList = true }) {
                        Label("Kết nối", systemImage: "server.rack")
                    }
                }
                
                ToolbarItem(placement: .automatic) {
                    Button(action: { showingAddConnection = true }) {
                        Label("Thêm kết nối", systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingConnectionsList) {
                ConnectionsListView(selectedConnection: $selectedConnection, isPresented: $showingConnectionsList)
                    .id(UUID()) // Đảm bảo view được tạo mới mỗi khi hiển thị
                    .presentationDetents([.height(450), .large])
                    .presentationDragIndicator(.visible)
                    .frame(minHeight: 450)
            }
            .sheet(isPresented: $showingAddConnection) {
                ConnectionFormView(connection: nil)
                    .onDisappear {
                        // Đảm bảo danh sách kết nối được làm mới sau khi thêm kết nối mới
                        modelContext.processPendingChanges()
                    }
            }
        }
    }
}

struct ConnectionFormView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    var connection: Connection?
    
    @State private var name: String = ""
    @State private var host: String = ""
    @State private var port: String = "27017"
    @State private var username: String = ""
    @State private var password: String = ""
    @State private var database: String = ""
    @State private var authDatabase: String = ""
    @State private var useSRV: Bool = false
    @State private var useSSL: Bool = false
    
    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Connection Details")) {
                    TextField("Connection Name", text: $name)
                    TextField("Host", text: $host)
                    if !useSRV {
                        TextField("Port", text: $port)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                    }
                    Toggle("Use SRV", isOn: $useSRV)
                    Toggle("Use SSL", isOn: $useSSL)
                }
                
                Section(header: Text("Authentication")) {
                    TextField("Username", text: $username)
                    SecureField("Password", text: $password)
                    TextField("Database", text: $database)
                    TextField("Auth Database", text: $authDatabase)
                }
            }
            .navigationTitle(connection == nil ? "Thêm kết nối" : "Chỉnh sửa kết nối")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Hủy") {
                        dismiss()
                    }
                }
                
                if connection != nil {
                    ToolbarItem(placement: .destructiveAction) {
                        Button(role: .destructive, action: {
                            deleteConnection()
                            dismiss()
                        }) {
                            Label("Xóa", systemImage: "trash")
                        }
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Lưu") {
                        saveConnection()
                        dismiss()
                    }
                    .disabled(name.isEmpty || host.isEmpty)
                }
            }
            .onAppear {
                if let connection = connection {
                    name = connection.name
                    host = connection.host
                    port = String(connection.port)
                    username = connection.username ?? ""
                    password = connection.password ?? ""
                    database = connection.database ?? ""
                    authDatabase = connection.authDatabase ?? ""
                    useSRV = connection.useSRV
                    useSSL = connection.useSSL
                }
            }
        }
    }
    
    private func saveConnection() {
        let portNumber = Int(port) ?? 27017
        
        if let connection = connection {
            // Update existing connection
            connection.name = name
            connection.host = host
            connection.port = portNumber
            connection.username = username.isEmpty ? nil : username
            connection.password = password.isEmpty ? nil : password
            connection.database = database.isEmpty ? nil : database
            connection.authDatabase = authDatabase.isEmpty ? nil : authDatabase
            connection.useSRV = useSRV
            connection.useSSL = useSSL
            try? modelContext.save()
        } else {
            // Create new connection
            let newConnection = Connection(
                name: name,
                host: host,
                port: portNumber,
                username: username.isEmpty ? nil : username,
                password: password.isEmpty ? nil : password,
                database: database.isEmpty ? nil : database,
                authDatabase: authDatabase.isEmpty ? nil : authDatabase,
                useSRV: useSRV,
                useSSL: useSSL
            )
            modelContext.insert(newConnection)
            try? modelContext.save()
        }
    }
    
    private func deleteConnection() {
        if let connection = connection {
            withAnimation {
                modelContext.delete(connection)
                try? modelContext.save()
            }
        }
    }
}

struct DatabaseView: View {
    var connection: Connection
    
    @State private var databases: [String] = []
    @State private var collections: [String] = []
    @State private var isLoading = false
    @State private var isConnected = false
    @State private var errorMessage: String? = nil
    @State private var selectedDatabase: String? = nil
    @State private var selectedCollection: String? = nil
    
    var body: some View {
        NavigationSplitView {
            VStack {
                // Connection info
                VStack(alignment: .leading) {
                    Text(connection.name)
                        .font(.headline)
                    Text(connection.host + (connection.useSRV ? " (SRV)" : ":" + String(connection.port)))
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(Color.gray.opacity(0.1))
                .cornerRadius(8)
                .padding(.horizontal)
                
                if !isConnected {
                    Button("Kết nối") {
                        Task {
                            await connect()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding()
                } else if isLoading {
                    ProgressView("Đang kết nối...")
                        .padding()
                } else if let error = errorMessage {
                    Text(error)
                        .foregroundColor(.red)
                        .padding()
                } else {
                    // Database selector
                    Picker("Cơ sở dữ liệu", selection: $selectedDatabase) {
                        Text("Chọn cơ sở dữ liệu").tag(nil as String?)
                        ForEach(databases, id: \.self) { database in
                            Text(database).tag(database as String?)
                        }
                    }
                    .pickerStyle(.menu)
                    .padding(.horizontal)
                    .onChange(of: selectedDatabase) { _, newValue in
                        if let dbName = newValue {
                            Task {
                                await loadCollections(for: dbName)
                            }
                        } else {
                            collections = []
                        }
                    }
                    
                    // Collections list
                    List(selection: $selectedCollection) {
                        if selectedDatabase == nil {
                            Text("Vui lòng chọn cơ sở dữ liệu")
                                .foregroundColor(.secondary)
                        } else if collections.isEmpty {
                            Text("Không tìm thấy collection")
                                .foregroundColor(.secondary)
                        } else {
                            ForEach(collections, id: \.self) { collection in
                                NavigationLink(value: collection) {
                                    Label(collection, systemImage: "tablecells")
                                }
                            }
                        }
                    }
                    .listStyle(.inset)
                }
            }
            .navigationTitle("Collections")
            .toolbar {
                if isConnected {
                    ToolbarItem(placement: .automatic) {
                        Button(action: {
                            if let dbName = selectedDatabase {
                                Task {
                                    await loadCollections(for: dbName)
                                }
                            } else {
                                Task {
                                    await loadDatabases()
                                }
                            }
                        }) {
                            Label("Làm mới", systemImage: "arrow.clockwise")
                        }
                    }
                }
            }
        } detail: {
            if let collection = selectedCollection, let database = selectedDatabase {
                DocumentsView(connection: connection, databaseName: database, collectionName: collection)
            } else {
                ContentUnavailableView("Chọn một Collection", systemImage: "tablecells", description: Text("Chọn một collection để xem dữ liệu"))
            }
        }
        .navigationTitle(connection.name)
    }
    
    private func connect() async {
        isLoading = true
        errorMessage = nil
        
        do {
            isConnected = try await MongoDBService.shared.connect(using: connection)
            if isConnected {
                await loadDatabases()
            } else {
                errorMessage = "Failed to connect to MongoDB server"
            }
        } catch {
            errorMessage = "Connection error: \(error.localizedDescription)"
            isConnected = false
        }
        
        isLoading = false
    }
    
    private func loadDatabases() async {
        isLoading = true
        errorMessage = nil
        
        do {
            databases = try await MongoDBService.shared.listDatabases(for: connection)
        } catch {
            errorMessage = "Không thể tải cơ sở dữ liệu: \(error.localizedDescription)"
        }
        
        isLoading = false
    }
    
    private func loadCollections(for databaseName: String) async {
        isLoading = true
        errorMessage = nil
        
        do {
            collections = try await MongoDBService.shared.listCollections(in: databaseName, for: connection)
        } catch {
            errorMessage = "Không thể tải collections: \(error.localizedDescription)"
        }
        
        isLoading = false
    }

}
