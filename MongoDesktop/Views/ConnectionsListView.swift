import SwiftUI

// MARK: - ConnectionsListView

struct ConnectionsListView: View {
    @EnvironmentObject private var connectionStore: ConnectionStore
    @Environment(\.openWindow) private var openWindow

    @State private var editorMode: EditorMode?
    @State private var draft = ConnectionDraft()
    @State private var hoveredId: UUID?
    @State private var selectedId: ConnectionProfile.ID?

    var body: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                stops: [
                    .init(color: Color(red: 0.06, green: 0.09, blue: 0.18), location: 0),
                    .init(color: Color(red: 0.04, green: 0.06, blue: 0.14), location: 0.5),
                    .init(color: Color(red: 0.08, green: 0.05, blue: 0.16), location: 1)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            // Decorative blobs
            GeometryReader { geo in
                Circle()
                    .fill(Color(red: 0.2, green: 0.4, blue: 0.9).opacity(0.18))
                    .frame(width: 300, height: 300)
                    .blur(radius: 80)
                    .offset(x: -60, y: -40)

                Circle()
                    .fill(Color(red: 0.5, green: 0.2, blue: 0.8).opacity(0.14))
                    .frame(width: 250, height: 250)
                    .blur(radius: 70)
                    .offset(x: geo.size.width - 120, y: geo.size.height - 100)
            }
            .ignoresSafeArea()

            VStack(spacing: 0) {
                header
                    .padding(.horizontal, 24)
                    .padding(.top, 28)
                    .padding(.bottom, 16)

                Divider()
                    .background(Color.white.opacity(0.06))

                connectionList
                    .padding(.top, 8)

                Divider()
                    .background(Color.white.opacity(0.06))

                footer
                    .padding(.horizontal, 24)
                    .padding(.vertical, 16)
            }
        }
        .frame(minWidth: 720, minHeight: 540)
        .sheet(item: $editorMode) { mode in
            ConnectionEditorView(mode: mode, draft: $draft, onSave: saveDraft)
        }
        .onChange(of: connectionStore.connections) { _, newValue in
            if let sid = selectedId, !newValue.contains(where: { $0.id == sid }) {
                selectedId = newValue.first?.id
            }
        }
    }

    // MARK: Header
    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Color(red: 0.2, green: 0.5, blue: 1.0), Color(red: 0.4, green: 0.2, blue: 0.9)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 36, height: 36)
                    Image(systemName: "leaf.fill")
                        .foregroundColor(.white)
                        .font(.system(size: 18, weight: .semibold))
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text("Mongo Desktop")
                        .font(.system(.title3, design: .rounded, weight: .bold))
                        .foregroundColor(.white)
                    Text("\(connectionStore.connections.count) connections")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.5))
                }
            }

            Spacer()

            HStack(spacing: 8) {
                GlassButton(label: "Thêm", icon: "plus") {
                    draft = ConnectionDraft()
                    editorMode = .create
                }

                GlassButton(label: "Sửa", icon: "pencil") {
                    guard let connection = selectedConnection else { return }
                    draft = ConnectionDraft(from: connection)
                    editorMode = .edit(connection.id)
                }
                .disabled(selectedConnection == nil)

                GlassButton(label: "Xóa", icon: "trash", isDestructive: true) {
                    guard let connection = selectedConnection else { return }
                    connectionStore.delete(connection)
                    if selectedId == connection.id { selectedId = nil }
                }
                .disabled(selectedConnection == nil)
            }
        }
    }

    // MARK: Connection List
    private var connectionList: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                if connectionStore.connections.isEmpty {
                    emptyState.padding(.top, 60)
                } else {
                    ForEach(connectionStore.connections) { connection in
                        ConnectionCard(
                            connection: connection,
                            isSelected: selectedId == connection.id,
                            isHovered: hoveredId == connection.id,
                            onSelect: { selectedId = connection.id },
                            onConnect: { openConnection(connection) }
                        )
                        .onHover { hovered in
                            hoveredId = hovered ? connection.id : nil
                        }
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
        }
    }

    // MARK: Footer
    private var footer: some View {
        HStack {
            Text("Double-click hoặc chọn rồi nhấn \"Kết nối\" để mở cửa sổ mới")
                .font(.caption)
                .foregroundColor(.white.opacity(0.3))

            Spacer()

            ConnectButton(isDisabled: selectedConnection == nil) {
                guard let connection = selectedConnection else { return }
                openConnection(connection)
            }
        }
    }

    // MARK: Empty State
    private var emptyState: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.04))
                    .frame(width: 80, height: 80)
                Image(systemName: "network.slash")
                    .font(.system(size: 32, weight: .light))
                    .foregroundStyle(.white.opacity(0.3))
            }
            Text("Không có connection nào")
                .font(.headline)
                .foregroundColor(.white.opacity(0.5))
            Text("Nhấn \"Thêm\" để tạo connection mới")
                .font(.caption)
                .foregroundColor(.white.opacity(0.3))
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Helpers
    private var selectedConnection: ConnectionProfile? {
        guard let sid = selectedId else { return nil }
        return connectionStore.connections.first { $0.id == sid }
    }

    /// Open a new window for this connection
    private func openConnection(_ connection: ConnectionProfile) {
        openWindow(value: connection.id)
    }

    private func saveDraft(mode: EditorMode) {
        switch mode {
        case .create: connectionStore.add(draft.build())
        case .edit(let id): connectionStore.update(draft.build(id: id))
        }
    }
}

// MARK: - ConnectionCard

struct ConnectionCard: View {
    let connection: ConnectionProfile
    let isSelected: Bool
    let isHovered: Bool
    let onSelect: () -> Void
    let onConnect: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            // Icon
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected
                          ? LinearGradient(colors: [Color(red: 0.2, green: 0.5, blue: 1.0), Color(red: 0.4, green: 0.2, blue: 0.9)], startPoint: .topLeading, endPoint: .bottomTrailing)
                          : LinearGradient(colors: [Color.white.opacity(0.08), Color.white.opacity(0.05)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 44, height: 44)
                Image(systemName: "server.rack")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(isSelected ? .white : .white.opacity(0.5))
            }

            // Info
            VStack(alignment: .leading, spacing: 3) {
                Text(connection.name)
                    .font(.system(.body, design: .rounded, weight: .semibold))
                    .foregroundColor(.white.opacity(0.9))
                Text(connection.connectionString)
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.35))
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let lastConnected = connection.lastConnectedAt {
                    Text("Kết nối lần cuối: \(lastConnected, style: .relative) trước")
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.25))
                }
            }

            Spacer()

            // Quick connect button on hover/select
            if isSelected || isHovered {
                Button(action: onConnect) {
                    Label("Mở cửa sổ", systemImage: "arrow.up.forward.app")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            LinearGradient(
                                colors: [Color(red: 0.2, green: 0.6, blue: 1.0), Color(red: 0.3, green: 0.3, blue: 0.9)],
                                startPoint: .leading,
                                endPoint: .trailing
                            ),
                            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                        )
                }
                .buttonStyle(.plain)
                .transition(.scale(scale: 0.9).combined(with: .opacity))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(isSelected
                      ? Color.white.opacity(0.08)
                      : (isHovered ? Color.white.opacity(0.04) : Color.white.opacity(0.02)))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(isSelected
                                ? Color(red: 0.3, green: 0.5, blue: 1.0).opacity(0.5)
                                : Color.white.opacity(0.07),
                                lineWidth: 1)
                )
        }
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .onTapGesture { onSelect() }
        .onTapGesture(count: 2) { onConnect() }
        .scaleEffect(isHovered && !isSelected ? 1.005 : 1.0)
        .animation(.spring(duration: 0.2), value: isHovered)
        .animation(.spring(duration: 0.2), value: isSelected)
    }
}

// MARK: - GlassButton

struct GlassButton: View {
    let label: String
    let icon: String
    var isDestructive: Bool = false
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon).font(.caption.weight(.semibold))
                Text(label).font(.caption.weight(.medium))
            }
            .foregroundColor(isDestructive ? Color(red: 1, green: 0.4, blue: 0.4) : .white.opacity(0.8))
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isHovered
                          ? (isDestructive ? Color(red: 1, green: 0.3, blue: 0.3).opacity(0.15) : Color.white.opacity(0.12))
                          : Color.white.opacity(0.07))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Color.white.opacity(0.12), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

// MARK: - ConnectButton

struct ConnectButton: View {
    let isDisabled: Bool
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: "arrow.up.forward.app").font(.body.weight(.semibold))
                Text("Kết nối").font(.body.weight(.semibold))
            }
            .foregroundColor(isDisabled ? .white.opacity(0.3) : .white)
            .padding(.horizontal, 20)
            .padding(.vertical, 9)
            .background {
                if !isDisabled {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: isHovered
                                    ? [Color(red: 0.3, green: 0.6, blue: 1.0), Color(red: 0.5, green: 0.3, blue: 1.0)]
                                    : [Color(red: 0.2, green: 0.5, blue: 0.9), Color(red: 0.4, green: 0.2, blue: 0.85)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .shadow(color: Color(red: 0.2, green: 0.4, blue: 1.0).opacity(0.4), radius: isHovered ? 12 : 6, y: 3)
                } else {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.white.opacity(0.06))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(Color.white.opacity(0.08), lineWidth: 1)
                        )
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .onHover { isHovered = $0 }
        .keyboardShortcut(.return, modifiers: [.command])
        .scaleEffect(isHovered && !isDisabled ? 1.02 : 1.0)
        .animation(.spring(duration: 0.2), value: isHovered)
    }
}

// MARK: - EditorMode

enum EditorMode: Identifiable {
    case create
    case edit(UUID)
    var id: String {
        switch self {
        case .create: return "create"
        case .edit(let id): return "edit-\(id.uuidString)"
        }
    }
}

// MARK: - ConnectionDraft

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
        name = connection.name; host = connection.host
        port = String(connection.port); username = connection.username
        password = connection.password; database = connection.database
        authDatabase = connection.authDatabase; useSRV = connection.useSRV; useSSL = connection.useSSL
    }

    func build(id: UUID = UUID()) -> ConnectionProfile {
        ConnectionProfile(
            id: id, name: name.isEmpty ? host : name,
            host: host.isEmpty ? "localhost" : host,
            port: Int(port) ?? 27017, username: username,
            password: password, database: database,
            authDatabase: authDatabase, useSRV: useSRV, useSSL: useSSL
        )
    }
}

// MARK: - ConnectionEditorView

struct ConnectionEditorView: View {
    let mode: EditorMode
    @Binding var draft: ConnectionDraft
    let onSave: (EditorMode) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(modeTitle).font(.title2.weight(.bold))
                    Text("Nhập thông tin kết nối MongoDB").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 24).padding(.top, 24).padding(.bottom, 20)

            Divider()

            ScrollView {
                VStack(spacing: 0) {
                    formSection(title: "Thông tin cơ bản") {
                        VStack(spacing: 12) {
                            formField(label: "Tên connection") { TextField("Ví dụ: Production DB", text: $draft.name) }
                            formField(label: "Host") { TextField("localhost", text: $draft.host) }
                            HStack(spacing: 12) {
                                formField(label: "Port") {
                                    TextField("27017", text: $draft.port).disabled(draft.useSRV)
                                }.frame(maxWidth: 120)

                                VStack(alignment: .leading, spacing: 6) {
                                    Text("Options").font(.caption.weight(.medium)).foregroundStyle(.secondary)
                                    VStack(alignment: .leading, spacing: 6) {
                                        Toggle("Dùng SRV (mongodb+srv)", isOn: $draft.useSRV)
                                        Toggle("TLS/SSL", isOn: $draft.useSSL)
                                    }.font(.callout)
                                }
                            }
                        }
                    }
                    Divider().padding(.horizontal, 24)
                    formSection(title: "Xác thực") {
                        VStack(spacing: 12) {
                            HStack(spacing: 12) {
                                formField(label: "Username") { TextField("Tùy chọn", text: $draft.username) }
                                formField(label: "Password") { SecureField("Tùy chọn", text: $draft.password) }
                            }
                            formField(label: "Database mặc định") { TextField("Tùy chọn", text: $draft.database) }
                            formField(label: "Auth Database") { TextField("Mặc định: admin", text: $draft.authDatabase) }
                        }
                    }
                }
                .padding(.vertical, 8)
            }

            Divider()

            HStack {
                Spacer()
                Button("Hủy") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Lưu") { onSave(mode); dismiss() }
                    .keyboardShortcut(.return, modifiers: [])
                    .buttonStyle(.borderedProminent)
                    .disabled(draft.host.isEmpty)
            }
            .padding(.horizontal, 24).padding(.vertical, 16)
        }
        .frame(width: 540)
        .background(.regularMaterial)
    }

    private var modeTitle: String {
        switch mode { case .create: return "Thêm connection"; case .edit: return "Sửa connection" }
    }

    @ViewBuilder
    private func formSection<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
            content()
        }
        .padding(.horizontal, 24).padding(.vertical, 16)
    }

    @ViewBuilder
    private func formField<Content: View>(label: String, @ViewBuilder field: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label).font(.caption.weight(.medium)).foregroundStyle(.secondary)
            field().textFieldStyle(.roundedBorder)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
