import SwiftUI

// MARK: - DatabaseBrowserView

struct DatabaseBrowserView: View {
    @EnvironmentObject private var connectionStore: ConnectionStore
    @EnvironmentObject private var appState: AppState
    @State private var showServerInfo = false

    var body: some View {
        NavigationSplitView {
            CollectionSidebarView()
                .environmentObject(appState)
        } detail: {
            DatabaseDetailView()
                .environmentObject(appState)
        }
        .navigationSplitViewStyle(.balanced)
        .navigationTitle(appState.connectionName)
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                Button(action: {
                    WindowCoordinator.shared.showConnectionsWindow()
                }) {
                    Image(systemName: "server.rack")
                }
                .help("Connections")

                DatabasePickerButton()
                    .environmentObject(appState)
            }

            ToolbarItemGroup(placement: .automatic) {
                QueryStatusView()
                    .environmentObject(appState)
            }

            ToolbarItemGroup(placement: .primaryAction) {
                Button(action: { showServerInfo.toggle() }) {
                    Image(systemName: "info.circle")
                }
                .help("Server Information")
                .popover(isPresented: $showServerInfo, arrowEdge: .bottom) {
                    ServerInfoPopoverView()
                }
            }
        }
        .toolbarBackground(.visible, for: .windowToolbar)
        .toolbarBackground(.ultraThinMaterial, for: .windowToolbar)
        .overlay(alignment: .topLeading) {
            if let error = appState.lastError {
                ErrorBannerView(message: error) { appState.lastError = nil }
                    .padding(12)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .animation(.spring(duration: 0.4), value: appState.lastError)
            }
        }
    }
}

// MARK: - CollectionSidebarView

struct CollectionSidebarView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Image(systemName: "folder.fill")
                    .foregroundStyle(.secondary)
                Text("Collections")
                    .font(.headline)
                Spacer()
                Text("\(appState.collections.count)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.quaternary, in: Capsule())
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            Divider().padding(.horizontal, 8)

            if appState.collections.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "tray")
                        .font(.largeTitle)
                        .foregroundStyle(.tertiary)
                    Text("Không có collection")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(appState.collections, id: \.self, selection: $appState.selectedCollection) { col in
                    Label(col, systemImage: "tablecells")
                        .font(.system(.body, design: .rounded))
                }
                .listStyle(.sidebar)
                .scrollContentBackground(.hidden)
                .onChange(of: appState.selectedCollection) { _, newValue in
                    guard let newValue, let db = appState.selectedDatabase else { return }
                    appState.currentPage = 0
                    Task { await appState.runFind(database: db, collection: newValue) }
                }
            }
        }
        .background(.regularMaterial)
    }
}

// MARK: - QueryStatusView

struct QueryStatusView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        HStack(spacing: 12) {
            // Connection Name
            HStack(spacing: 6) {
                Circle()
                    .fill(Color.green)
                    .frame(width: 7, height: 7)
                Text(appState.connectionName)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
            }

            // Database Name
            if let db = appState.selectedDatabase {
                Divider().frame(height: 14)
                
                HStack(spacing: 4) {
                    Image(systemName: "cylinder.split.1x2")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(db)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                }
            }

            // Collection Name
            if let col = appState.selectedCollection {
                Divider().frame(height: 14)
                
                HStack(spacing: 4) {
                    Image(systemName: "tablecells")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(col)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                }
            }

            if appState.isLoading || appState.lastQueryDuration != nil {
                Divider().frame(height: 14)
            }
            
            if appState.isLoading {
                ProgressView()
                    .controlSize(.mini)
                    .frame(width: 12, height: 12)
                    .fixedSize()
                    .opacity(appState.isLoading ? 1 : 0)
            } else {
                HStack(spacing: 4) {
                    Image(systemName: "clock")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(appState.lastQueryDuration.map { formattedDuration($0) } ?? "0ms")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func formattedDuration(_ seconds: TimeInterval) -> String {
        if seconds < 1 {
            return "\(Int(seconds * 1000))ms"
        } else {
            return String(format: "%.2fs", seconds)
        }
    }
}

// MARK: - ErrorBannerView

struct ErrorBannerView: View {
    let message: String
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(message)
                .font(.callout)
                .lineLimit(2)
            Spacer()
            Button(action: onDismiss) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.orange.opacity(0.4), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.12), radius: 8, y: 4)
    }
}
