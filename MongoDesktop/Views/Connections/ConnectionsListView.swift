import SwiftUI

// MARK: - ConnectionsListView

struct ConnectionsListView: View {
    @EnvironmentObject private var connectionStore: ConnectionStore
    @Environment(\.openWindow) private var openWindow

    @State private var editorMode: EditorMode?
    @State private var draft = ConnectionDraft()
    @State private var selectedId: ConnectionProfile.ID?
    @State private var importURI: String = ""
    @State private var showImportAlert = false

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detailContent
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 700, minHeight: 460)
        .sheet(item: $editorMode) { mode in
            ConnectionEditorView(mode: mode, draft: $draft, onSave: saveDraft)
        }
        .alert("Import từ URI", isPresented: $showImportAlert) {
            TextField("mongodb://host:port/db", text: $importURI)
            Button("Hủy", role: .cancel) { importURI = "" }
            Button("Import") { importFromURI() }
        } message: {
            Text("Dán connection string MongoDB vào đây")
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(spacing: 0) {
            // Logo / branding
            VStack(spacing: 6) {
                Image(systemName: "leaf.fill")
                    .font(.system(size: 36, weight: .medium))
                    .foregroundStyle(.green)
                    .padding(.top, 28)

                Text("Mongo Desktop")
                    .font(.system(.title3, design: .rounded, weight: .bold))

                Text("\(connectionStore.connections.count) connections")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.bottom, 24)

            Divider().padding(.horizontal, 16)

            Spacer()

            // Action buttons
            VStack(spacing: 8) {
                Button(action: {
                    draft = ConnectionDraft()
                    editorMode = .create
                }) {
                    Label("New Server...", systemImage: "plus")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 6, style: .continuous))

                Button(action: { showImportAlert = true }) {
                    Label("Import URI", systemImage: "square.and.arrow.down")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
        .frame(minWidth: 180, idealWidth: 200)
        .background(.ultraThinMaterial)
    }

    // MARK: - Detail Content

    private var detailContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Quick Connect bar
            quickConnectBar
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 12)

            Divider().padding(.horizontal, 16)

            // Connection list
            if connectionStore.connections.isEmpty {
                emptyState
            } else {
                connectionList
            }
        }
        .background(.ultraThinMaterial)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button(action: {
                    guard let conn = selectedConnection else { return }
                    draft = ConnectionDraft(from: conn)
                    editorMode = .edit(conn.id)
                }) {
                    Label("Edit", systemImage: "pencil")
                }
                .disabled(selectedConnection == nil)
                .help("Sửa connection")

                Button(action: deleteSelected) {
                    Label("Delete", systemImage: "trash")
                }
                .disabled(selectedConnection == nil)
                .help("Xóa connection")
            }
        }
    }

    // MARK: - Quick Connect

    private var quickConnectBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Quick Connect")
                .font(.headline)

            HStack(spacing: 8) {
                Image(systemName: "link")
                    .foregroundStyle(.secondary)
                TextField("mongodb://localhost:27017", text: $importURI)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                    .onSubmit { quickConnect() }

                Button("Connect") { quickConnect() }
                    .buttonStyle(.borderedProminent)
                    .disabled(importURI.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    // MARK: - Connection List

    private var connectionList: some View {
        List(connectionStore.connections, selection: $selectedId) { connection in
            ConnectionRow(connection: connection, onConnect: {
                openWindow(value: connection.id)
            })
            .tag(connection.id)
        }
        .listStyle(.inset(alternatesRowBackgrounds: true))
        .scrollContentBackground(.hidden)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "server.rack")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(.tertiary)
            Text("Chưa có connection nào")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("Nhấn \"New Server\" hoặc dán URI ở Quick Connect")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Helpers

    private var selectedConnection: ConnectionProfile? {
        guard let sid = selectedId else { return nil }
        return connectionStore.connections.first { $0.id == sid }
    }

    private func deleteSelected() {
        guard let connection = selectedConnection else { return }
        connectionStore.delete(connection)
        if selectedId == connection.id { selectedId = nil }
    }

    private func importFromURI() {
        let uri = importURI.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !uri.isEmpty else { return }
        let draft = ConnectionDraft(fromURI: uri)
        let profile = draft.build()
        connectionStore.add(profile)
        importURI = ""
    }

    private func quickConnect() {
        let uri = importURI.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !uri.isEmpty else { return }

        // Save as a connection first, then open window
        let draft = ConnectionDraft(fromURI: uri)
        let profile = draft.build()
        connectionStore.add(profile)
        importURI = ""

        // Open database window
        openWindow(value: profile.id)
    }

    private func saveDraft(mode: EditorMode) {
        switch mode {
        case .create: connectionStore.add(draft.build())
        case .edit(let id): connectionStore.update(draft.build(id: id))
        }
    }
}

// MARK: - ConnectionRow

struct ConnectionRow: View {
    let connection: ConnectionProfile
    let onConnect: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // Icon
            Image(systemName: "server.rack")
                .font(.title3)
                .foregroundStyle(.secondary)
                .frame(width: 28)

            // Info
            VStack(alignment: .leading, spacing: 2) {
                Text(connection.name)
                    .font(.system(.body, design: .rounded, weight: .medium))
                Text(connection.connectionString)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            // Connect button
            Button("Connect", action: onConnect)
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { onConnect() }
    }
}
