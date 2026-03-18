import SwiftUI

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

    /// Parse a MongoDB URI string into a draft
    init(fromURI uri: String) {
        let trimmed = uri.trimmingCharacters(in: .whitespacesAndNewlines)

        // Detect SRV
        if trimmed.hasPrefix("mongodb+srv://") {
            useSRV = true
        }

        // Detect SSL/TLS from query params
        if trimmed.contains("ssl=true") || trimmed.contains("tls=true") {
            useSSL = true
        }

        // Parse using URLComponents (replace mongodb:// with http:// for parsing)
        var httpURI = trimmed
        if httpURI.hasPrefix("mongodb+srv://") {
            httpURI = "http://" + httpURI.dropFirst("mongodb+srv://".count)
        } else if httpURI.hasPrefix("mongodb://") {
            httpURI = "http://" + httpURI.dropFirst("mongodb://".count)
        }

        guard let components = URLComponents(string: httpURI) else { return }

        if let user = components.user, !user.isEmpty {
            username = user
        }
        if let pass = components.password, !pass.isEmpty {
            password = pass
        }
        if let h = components.host, !h.isEmpty {
            host = h
        }
        if let p = components.port {
            port = String(p)
        } else if useSRV {
            port = ""
        }

        // Path = database name
        let path = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if !path.isEmpty {
            database = path
        }

        // Check authSource in query
        if let queryItems = components.queryItems {
            for item in queryItems {
                if item.name == "authSource", let val = item.value, !val.isEmpty {
                    authDatabase = val
                }
            }
        }

        // Generate name from host
        name = host
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

// MARK: - ConnectionEditorView

struct ConnectionEditorView: View {
    let mode: EditorMode
    @Binding var draft: ConnectionDraft
    let onSave: (EditorMode) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var isTestingConnection = false
    @State private var showTestAlert = false
    @State private var testAlertTitle = ""
    @State private var testAlertMessage = ""
    @State private var showTestDebug = false
    @State private var testDebugText = ""
    @State private var isDebuggingDNS = false
    @State private var showDNSDebug = false
    @State private var dnsDebugText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(modeTitle)
                        .font(.title2.weight(.bold))
                    Text("Nhập thông tin kết nối MongoDB")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 24)
            .padding(.top, 12)
            .padding(.bottom, 12)

            Divider()

            ScrollView {
                VStack(spacing: 0) {
                    formSection(title: "Thông tin cơ bản") {
                        VStack(spacing: 12) {
                            formField(label: "Tên connection") {
                                TextField("Ví dụ: Production DB", text: $draft.name)
                            }
                            formField(label: "Host") {
                                TextField("localhost", text: $draft.host)
                            }
                            HStack(spacing: 12) {
                                formField(label: "Port") {
                                    TextField("27017", text: $draft.port)
                                        .disabled(draft.useSRV)
                                }
                                .frame(maxWidth: 120)

                                VStack(alignment: .leading, spacing: 6) {
                                    Text("Options")
                                        .font(.caption.weight(.medium))
                                        .foregroundStyle(.secondary)
                                    VStack(alignment: .leading, spacing: 6) {
                                        Toggle("Dùng SRV (mongodb+srv)", isOn: $draft.useSRV)
                                        Toggle("TLS/SSL", isOn: $draft.useSSL)
                                    }
                                    .font(.callout)
                                }
                            }
                        }
                    }

                    Divider().padding(.horizontal, 24)

                    formSection(title: "Xác thực") {
                        VStack(spacing: 12) {
                            HStack(spacing: 12) {
                                formField(label: "Username") {
                                    TextField("Tùy chọn", text: $draft.username)
                                }
                                formField(label: "Password") {
                                    SecureField("Tùy chọn", text: $draft.password)
                                }
                            }
                            formField(label: "Database mặc định") {
                                TextField("Tùy chọn", text: $draft.database)
                            }
                            formField(label: "Auth Database") {
                                TextField("Mặc định: admin", text: $draft.authDatabase)
                            }
                        }
                    }
                }
                .padding(.vertical, 8)
            }

            Divider()

            // Footer buttons
            HStack {
                Spacer()
                Button(action: runTestConnection) {
                    HStack(spacing: 8) {
                        if isTestingConnection {
                            ProgressView()
                                .controlSize(.small)
                        }
                        Text(isTestingConnection ? "Đang kiểm tra..." : "Kiểm tra kết nối")
                    }
                }
                .disabled(draft.host.isEmpty || isTestingConnection)
                .buttonStyle(.bordered)
                Button(action: runDNSDebug) {
                    HStack(spacing: 8) {
                        if isDebuggingDNS {
                            ProgressView()
                                .controlSize(.small)
                        }
                        Text(isDebuggingDNS ? "Đang debug..." : "Debug DNS")
                    }
                }
                .disabled(draft.host.isEmpty || isDebuggingDNS)
                .buttonStyle(.bordered)
                Button("Lưu") { onSave(mode); dismiss() }
                    .keyboardShortcut(.return, modifiers: [])
                    .buttonStyle(.borderedProminent)
                    .disabled(draft.host.isEmpty)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
        }
        .frame(width: 540)
        .background(.regularMaterial)
        .alert(testAlertTitle, isPresented: $showTestAlert) {
            if !testDebugText.isEmpty {
                Button("Chi tiết") { showTestDebug = true }
            }
            Button("OK", role: .cancel) {}
        } message: {
            Text(testAlertMessage)
        }
        .sheet(isPresented: $showTestDebug) {
            DNSDebugSheet(text: testDebugText)
        }
        .sheet(isPresented: $showDNSDebug) {
            DNSDebugSheet(text: dnsDebugText)
        }
    }

    private var modeTitle: String {
        switch mode {
        case .create: return "Thêm connection"
        case .edit: return "Sửa connection"
        }
    }

    @ViewBuilder
    private func formSection<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            content()
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
    }

    @ViewBuilder
    private func formField<Content: View>(label: String, @ViewBuilder field: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            field()
                .textFieldStyle(.roundedBorder)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func runTestConnection() {
        isTestingConnection = true
        testDebugText = ""
        let uri = draft.build().connectionString
        Task {
            do {
                try await MongoService.shared.testConnection(uri: uri)
                await MainActor.run {
                    testAlertTitle = "Kết nối thành công"
                    testAlertMessage = "Đã ping MongoDB thành công."
                    showTestAlert = true
                    isTestingConnection = false
                }
            } catch {
                let debugText = await MongoService.shared.debugConnection(uri: uri)
                await MainActor.run {
                    testAlertTitle = "Kết nối thất bại"
                    testAlertMessage = error.localizedDescription
                    testDebugText = debugText
                    showTestAlert = true
                    isTestingConnection = false
                }
            }
        }
    }

    private func runDNSDebug() {
        isDebuggingDNS = true
        dnsDebugText = ""
        let uri = draft.build().connectionString
        Task {
            let text = await MongoService.shared.debugDNS(uri: uri)
            await MainActor.run {
                dnsDebugText = text
                showDNSDebug = true
                isDebuggingDNS = false
            }
        }
    }
}

private struct DNSDebugSheet: View {
    let text: String
    @Environment(\.dismiss) private var dismiss
    @State private var didCopy = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("DNS Debug")
                    .font(.headline)
                Spacer()
                if didCopy {
                    Text("Đã copy")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Button("Copy") { copyText() }
                Button("Đóng") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(.bottom, 4)

            ScrollView {
                Text(text.isEmpty ? "Không có dữ liệu." : text)
                    .font(.system(.body, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .frame(minHeight: 300)
        }
        .padding(20)
        .frame(width: 640, height: 480)
    }

    private func copyText() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        didCopy = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            didCopy = false
        }
    }
}
