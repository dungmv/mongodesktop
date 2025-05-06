//
//  ConnectionsListView.swift
//  MongoDesktop
//
//  Created by Trae AI on 21/4/25.
//

import SwiftUI
import SwiftData

struct ConnectionsListView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Connection.name) private var connections: [Connection]
    
    @Binding var selectedConnection: Connection?
    @Binding var isPresented: Bool
    
    @State private var showingAddConnection = false
    
    var body: some View {
        NavigationStack {
            Group {
                if connections.isEmpty {
                    ContentUnavailableView("Không có kết nối", systemImage: "server.rack", description: Text("Bạn chưa thêm kết nối MongoDB nào"))
                } else {
                    List {
                        ForEach(connections) { connection in
                            Button {
                                selectedConnection = connection
                                isPresented = false
                            } label: {
                                VStack(alignment: .leading) {
                                    Text(connection.name)
                                        .font(.headline)
                                    Text(connection.host + (connection.useSRV ? " (SRV)" : ":" + String(connection.port)))
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                        .onDelete(perform: deleteConnections)
                    }
                }
            }
            .navigationTitle("Danh sách kết nối")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Đóng") {
                        isPresented = false
                    }
                }
                
                ToolbarItem(placement: .automatic) {
                    Button(action: { showingAddConnection = true }) {
                        Label("Thêm kết nối", systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingAddConnection) {
                ConnectionFormView(connection: nil)
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