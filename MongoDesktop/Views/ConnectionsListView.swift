import SwiftUI

struct ConnectionsListView: View {
    @EnvironmentObject private var connectionStore: ConnectionStore
    @EnvironmentObject private var appState: AppState
    @Environment(\.openWindow) private var openWindow

    @State private var editorMode: EditorMode?
    @State private var draft = ConnectionDraft()

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color.black.opacity(0.08), Color.blue.opacity(0.15), Color.clear],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                header
                Divider()
                content
            }
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .padding(12)
        }
        .frame(minWidth: 700, minHeight: 500)
        .sheet(item: $editorMode) { mode in
            ConnectionEditorView(
                mode: mode,
                draft: $draft,
                onSave: saveDraft
            )
        }
        .onChange(of: appState.isConnected) { _, isConnected in
            if isConnected {
                openWindow(id: "main")
            }
        }
        .onAppear {
            if appState.selectedConnectionId == nil {
                appState.selectedConnectionId = connectionStore.connections.first?.id
            }
        }
        .onChange(of: connectionStore.connections) { _, newValue in
            if let selectedId = appState.selectedConnectionId,
               !newValue.contains(where: { $0.id == selectedId }) {
                appState.selectedConnectionId = newValue.first?.id
            }
        }
    }

    private var header: some View {
        HStack {
            Text("Connections")
                .font(.title2)
                .bold()

            Spacer()

            Button("Kết nối") {
                connectSelected()
            }
            .keyboardShortcut(.return, modifiers: [.command])
            .disabled(selectedConnection == nil)

            Button("Thêm") {
                draft = ConnectionDraft()
                editorMode = .create
            }

            Button("Sửa") {
                guard let connection = selectedConnection else { return }
                draft = ConnectionDraft(from: connection)
                editorMode = .edit(connection.id)
            }
            .disabled(selectedConnection == nil)

            Button("Xóa") {
                guard let connection = selectedConnection else { return }
                connectionStore.delete(connection)
                if appState.selectedConnectionId == connection.id {
                    appState.selectedConnectionId = nil
                    appState.disconnect()
                }
            }
            .disabled(selectedConnection == nil)
        }
        .padding(16)
    }

    private var content: some View {
        List(connectionStore.connections, selection: $appState.selectedConnectionId) { connection in
            VStack(alignment: .leading, spacing: 4) {
                Text(connection.name)
                    .font(.headline)
                Text(connection.connectionString)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
            .onTapGesture(count: 2) {
                appState.selectedConnectionId = connection.id
                appState.connect(using: connection, store: connectionStore)
            }
        }
        .scrollContentBackground(.hidden)
        .background(.regularMaterial)
    }

    private var selectedConnection: ConnectionProfile? {
        guard let selectedId = appState.selectedConnectionId else { return nil }
        return connectionStore.connections.first { $0.id == selectedId }
    }

    private func saveDraft(mode: EditorMode) {
        switch mode {
        case .create:
            connectionStore.add(draft.build())
        case .edit(let id):
            connectionStore.update(draft.build(id: id))
        }
    }

    private func connectSelected() {
        guard let connection = selectedConnection else { return }
        appState.connect(using: connection, store: connectionStore)
    }
}

enum EditorMode: Identifiable {
    case create
    case edit(UUID)

    var id: String {
        switch self {
        case .create:
            return "create"
        case .edit(let id):
            return "edit-\(id.uuidString)"
        }
    }
}

struct ConnectionDraft {
    var name: String = ""
    var host: String = "localhost"
    var port: String = "27017"
    var username: String = ""
    var password: String = ""
    var database: String = ""
    var authDatabase: String = ""
    var useSRV: Bool = false
    var useSSL: Bool = false

    init() {}

    init(from connection: ConnectionProfile) {
        name = connection.name
        host = connection.host
        port = String(connection.port)
        username = connection.username
        password = connection.password
        database = connection.database
        authDatabase = connection.authDatabase
        useSRV = connection.useSRV
        useSSL = connection.useSSL
    }

    func build(id: UUID = UUID()) -> ConnectionProfile {
        ConnectionProfile(
            id: id,
            name: name.isEmpty ? host : name,
            host: host.isEmpty ? "localhost" : host,
            port: Int(port) ?? 27017,
            username: username,
            password: password,
            database: database,
            authDatabase: authDatabase,
            useSRV: useSRV,
            useSSL: useSSL
        )
    }
}

struct ConnectionEditorView: View {
    let mode: EditorMode
    @Binding var draft: ConnectionDraft
    let onSave: (EditorMode) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(modeTitle)
                .font(.title2)
                .bold()

            form

            HStack {
                Spacer()
                Button("Hủy") { dismiss() }
                Button("Lưu") {
                    onSave(mode)
                    dismiss()
                }
                .keyboardShortcut(.return, modifiers: [])
                .disabled(draft.host.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 520)
    }

    private var modeTitle: String {
        switch mode {
        case .create:
            return "Thêm connection"
        case .edit:
            return "Sửa connection"
        }
    }

    private var form: some View {
        VStack(spacing: 12) {
            TextField("Tên connection", text: $draft.name)
            TextField("Host", text: $draft.host)
            TextField("Port", text: $draft.port)
                .disabled(draft.useSRV)

            HStack(spacing: 12) {
                TextField("Username", text: $draft.username)
                SecureField("Password", text: $draft.password)
            }

            TextField("Database mặc định", text: $draft.database)
            TextField("Auth Database", text: $draft.authDatabase)

            Toggle("Dùng SRV (mongodb+srv)", isOn: $draft.useSRV)
            Toggle("TLS/SSL", isOn: $draft.useSSL)
        }
        .textFieldStyle(.roundedBorder)
    }
}
