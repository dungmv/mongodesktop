import SwiftUI

// MARK: - DatabaseWindowView

struct DatabaseWindowView: View {
    let connectionId: ConnectionProfile.ID?

    @EnvironmentObject private var connectionStore: ConnectionStore
    @StateObject private var windowState = AppState()

    var body: some View {
        Group {
            if windowState.isConnected {
                DatabaseBrowserView()
                    .environmentObject(windowState)
                    .environmentObject(connectionStore)
            } else if windowState.isLoading {
                connectingView
            } else {
                failedView
            }
        }
        .onAppear { connectOnAppear() }
        .onDisappear {
            Task {
                try? await windowState.disconnect()
            }
            // Hiện lại cửa sổ Connections khi Database window đóng
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                WindowCoordinator.shared.showConnectionsWindow()
            }
        }
        .frame(minWidth: 900, minHeight: 600)
    }

    private var connectingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .controlSize(.large)
                .frame(width: 20, height: 20)
                .fixedSize()
            Text("Đang kết nối…")
                .font(.headline)
                .foregroundStyle(.secondary)
            if let connection = resolvedConnection {
                Text(connection.connectionString)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .padding(.horizontal, 40)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var failedView: some View {
        VStack(spacing: 16) {
            Image(systemName: "network.slash")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(.secondary)
            Text("Không thể kết nối")
                .font(.title2.weight(.semibold))
            if let error = windowState.lastError {
                Text(error)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
            Button("Thử lại") { connectOnAppear() }
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var resolvedConnection: ConnectionProfile? {
        guard let id = connectionId else { return nil }
        return connectionStore.connections.first { $0.id == id }
    }

    private func connectOnAppear() {
        guard let connection = resolvedConnection else { return }
        windowState.connect(using: connection, store: connectionStore)
    }
}
