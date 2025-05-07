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
    
    // Đảm bảo danh sách kết nối được làm mới khi view xuất hiện
    @State private var refreshTrigger = false
    @State private var showingAddConnection = false
    @State private var connectionToEdit: Connection? = nil
    @State private var showingEditConnection = false
    
    var body: some View {
        NavigationStack {
            Group {
                if connections.isEmpty {
                    ContentUnavailableView("Không có kết nối", systemImage: "server.rack", description: Text("Bạn chưa thêm kết nối MongoDB nào"))
                        .frame(minHeight: 300) // Đảm bảo chiều cao tối thiểu
                } else {
                    Text("Chọn một kết nối để tiếp tục")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .padding(.horizontal)
                        .padding(.top, 8)
                    
                    List {
                        ForEach(connections) { connection in
                            Button {
                                selectedConnection = connection
                                isPresented = false
                            } label: {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(connection.name)
                                        .font(.headline)
                                        .foregroundColor(.primary)
                                    Text(connection.host + (connection.useSRV ? " (SRV)" : ":" + String(connection.port)))
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                }
                                .padding(.vertical, 8)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                                .background(Color.gray.opacity(0.05))
                                .cornerRadius(8)
                            }
                            .buttonStyle(.plain)
                            .padding(.vertical, 2)
                            .contextMenu {
                                Button(action: {
                                    editConnection(connection)
                                }) {
                                    Label("Chỉnh sửa", systemImage: "pencil")
                                }
                                
                                Button(role: .destructive, action: {
                                    if let index = connections.firstIndex(where: { $0 === connection }) {
                                        deleteConnections(offsets: IndexSet(integer: index))
                                    }
                                }) {
                                    Label("Xóa", systemImage: "trash")
                                }
                            }
                        }
                        .onDelete(perform: deleteConnections)
                    }
                    .frame(minHeight: 300) // Đảm bảo danh sách có chiều cao tối thiểu
                }
            }
            .onAppear {
                // Đảm bảo danh sách kết nối được làm mới khi view xuất hiện
                refreshTrigger.toggle()
                modelContext.processPendingChanges()
                try? modelContext.save()
            }
            .navigationTitle("Danh sách kết nối")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Đóng") {
                        isPresented = false
                    }
                }
                
                ToolbarItem(placement: .primaryAction) {
                    Button(action: { showingAddConnection = true }) {
                        Label("Thêm kết nối", systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingAddConnection) {
                ConnectionFormView(connection: nil)
                    .onDisappear {
                        // Đảm bảo danh sách kết nối được làm mới sau khi thêm kết nối mới
                        modelContext.processPendingChanges()
                        try? modelContext.save()
                    }
            }
            .sheet(isPresented: $showingEditConnection) {
                if let connectionToEdit = connectionToEdit {
                    ConnectionFormView(connection: connectionToEdit)
                        .onDisappear {
                            // Đảm bảo danh sách kết nối được làm mới sau khi chỉnh sửa kết nối
                            modelContext.processPendingChanges()
                            try? modelContext.save()
                        }
                }
            }
        }
    }
    
    private func deleteConnections(offsets: IndexSet) {
        withAnimation {
            for index in offsets {
                modelContext.delete(connections[index])
            }
            // Đảm bảo các thay đổi được lưu lại
            try? modelContext.save()
        }
    }
    
    private func editConnection(_ connection: Connection) {
        connectionToEdit = connection
        showingEditConnection = true
    }
}