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
    @State private var selectedConnection: Connection?
    
    var body: some View {
        NavigationSplitView {
            List(selection: $selectedConnection) {
                ForEach(connections) { connection in
                    NavigationLink(value: connection) {
                        VStack(alignment: .leading) {
                            Text(connection.name)
                                .font(.headline)
                            Text(connection.host + (connection.useSRV ? " (SRV)" : ":" + String(connection.port)))
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .onDelete(perform: deleteConnections)
            }
            .navigationTitle("Connections")
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    Button(action: { showingAddConnection = true }) {
                        Label("Add Connection", systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingAddConnection) {
                ConnectionFormView(connection: nil)
            }
        } detail: {
            if let connection = selectedConnection {
                DatabaseView(connection: connection)
            } else {
                Text("Select a connection")
                    .foregroundColor(.secondary)
            }
        }
    }
    
    private func deleteConnections(offsets: IndexSet) {
        withAnimation {
            for index in offsets {
                modelContext.delete(connections[index])
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
            .navigationTitle(connection == nil ? "Add Connection" : "Edit Connection")
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .automatic) {
                    Button("Save") {
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
        }
    }
}

struct DatabaseView: View {
    var connection: Connection
    
    @State private var databases: [String] = []
    @State private var isLoading = false
    @State private var isConnected = false
    @State private var errorMessage: String? = nil
    @State private var selectedDatabase: String? = nil
    
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
                
                // Database list
                List(selection: $selectedDatabase) {
                    if isLoading {
                        ProgressView("Connecting...")
                    } else if let error = errorMessage {
                        Text(error)
                            .foregroundColor(.red)
                    } else if !isConnected {
                        Button("Connect") {
                            Task {
                                await connect()
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .frame(maxWidth: .infinity, alignment: .center)
                    } else if databases.isEmpty {
                        Text("No databases found")
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(databases, id: \.self) { database in
                            NavigationLink(value: database) {
                                Label(database, systemImage: "server.rack")
                            }
                        }
                    }
                }
                .listStyle(.inset)
            }
            .navigationTitle("Databases")
            .toolbar {
                if isConnected {
                    ToolbarItem(placement: .automatic) {
                        Button(action: {
                            Task {
                                await loadDatabases()
                            }
                        }) {
                            Label("Refresh", systemImage: "arrow.clockwise")
                        }
                    }
                }
            }
        } detail: {
            if let database = selectedDatabase {
                DatabaseDetailView(connection: connection, databaseName: database)
            } else {
                ContentUnavailableView("Select a Database", systemImage: "server.rack", description: Text("Choose a database to view its collections"))
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
            errorMessage = "Failed to load databases: \(error.localizedDescription)"
        }
        
        isLoading = false
    }

}
