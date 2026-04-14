import SwiftUI
import AppKit

// MARK: - DatabaseBrowserView

struct DatabaseBrowserView: View {
    @EnvironmentObject private var connectionStore: ConnectionStore
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var tabState: QueryTabState
    @Environment(\.addDatabaseTab) private var addDatabaseTab
    @State private var showServerInfo = false

    var body: some View {
        NavigationSplitView {
            CollectionSidebarView()
                .environmentObject(appState)
                .environmentObject(tabState)
        } detail: {
            DatabaseDetailView()
                .environmentObject(appState)
                .environmentObject(tabState)
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

                DatabaseCollectionInlineView()
                    .environmentObject(appState)
            }

            ToolbarItem(placement: .principal) {
                ConnectionStatusCenterView(showServerInfo: $showServerInfo)
                    .environmentObject(appState)
                    .environmentObject(tabState)
            }

            ToolbarItemGroup(placement: .primaryAction) {
                Button(action: addDatabaseTab) {
                    Image(systemName: "plus")
                        .font(.caption.weight(.semibold))
                }
                .help("New Tab")
            }
        }
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
    @EnvironmentObject private var tabState: QueryTabState
    @Environment(\.databaseTabContext) private var tabContext
    @State private var collectionFilterText = ""

    private var filteredCollections: [String] {
        let keyword = collectionFilterText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keyword.isEmpty else { return appState.collections }
        return appState.collections.filter { $0.localizedCaseInsensitiveContains(keyword) }
    }

    private func iconName(for collection: String) -> String {
        if appState.timeSeriesCollections.contains(collection) {
            return "chart.xyaxis.line"
        }
        return "tablecells"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Image(systemName: "folder.fill")
                    .foregroundStyle(.secondary)
                Text("Collections")
                    .font(.headline)
                Spacer()
                Text("\(filteredCollections.count)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.quaternary, in: Capsule())
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Filter collections", text: $collectionFilterText)
                    .textFieldStyle(.plain)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
            .padding(.horizontal, 10)
            .padding(.bottom, 8)

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
            } else if filteredCollections.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.title2)
                        .foregroundStyle(.tertiary)
                    Text("Không tìm thấy collection")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(filteredCollections, id: \.self) { col in
                    let isSelected = col == appState.selectedCollection
                    Label(col, systemImage: iconName(for: col))
                        .font(.system(.body, design: .rounded))
                        .foregroundStyle(isSelected ? .white : .primary)
                        .padding(.vertical, 6)
                        .padding(.horizontal, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(isSelected ? Color.accentColor : Color.clear)
                        )
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if let db = appState.selectedDatabase {
                                tabContext?.open(db, col)
                            }
                        }
                }
                .listStyle(.sidebar)
                .scrollContentBackground(.hidden)
            }
        }
        .background(.ultraThinMaterial)
    }
}

// MARK: - DatabaseCollectionInlineView

struct DatabaseCollectionInlineView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let db = appState.selectedDatabase, !db.isEmpty {
                Text(db)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }

            if let col = appState.selectedCollection, !col.isEmpty {
                Text(col)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.trailing, 8)
    }
}

// MARK: - Titlebar Leading Content

struct TitlebarLeadingContent: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        HStack(spacing: 10) {
            Button(action: {
                WindowCoordinator.shared.showConnectionsWindow()
            }) {
                Image(systemName: "server.rack")
            }
            .help("Connections")

            DatabasePickerButton()
                .environmentObject(appState)

            DatabaseCollectionInlineView()
                .environmentObject(appState)
        }
        .padding(.leading, 6)
    }
}

// MARK: - Titlebar Leading Accessory Host

struct TitlebarLeadingAccessoryHost<Content: View>: NSViewRepresentable {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        NSView(frame: .zero)
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        if context.coordinator.hostingView == nil {
            context.coordinator.hostingView = NSHostingView(rootView: content)
        } else {
            context.coordinator.hostingView?.rootView = content
        }

        guard let window = nsView.window,
              let hostingView = context.coordinator.hostingView
        else { return }

        if context.coordinator.controller == nil {
            let controller = NSTitlebarAccessoryViewController()
            controller.view = hostingView
            controller.layoutAttribute = .leading
            window.addTitlebarAccessoryViewController(controller)
            context.coordinator.controller = controller
        } else if context.coordinator.controller?.view !== hostingView {
            context.coordinator.controller?.view = hostingView
        }
    }

    final class Coordinator {
        var controller: NSTitlebarAccessoryViewController?
        var hostingView: NSHostingView<Content>?
    }
}

// MARK: - ConnectionStatusCenterView

struct ConnectionStatusCenterView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var tabState: QueryTabState
    @Binding var showServerInfo: Bool

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 6) {
                Button(action: { showServerInfo.toggle() }) {
                    Image(systemName: "info.circle")
                }
                .buttonStyle(.plain)
                .help("Server Information")
                .popover(isPresented: $showServerInfo, arrowEdge: .bottom) {
                    ServerInfoPopoverView()
                }

                Text(appState.connectionName)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
            }

            Spacer(minLength: 12)

            if tabState.isLoading || tabState.lastQueryDuration != nil {
                HStack(spacing: 8) {
                    Divider().frame(height: 14)

                    if tabState.isLoading {
                        ProgressView()
                            .controlSize(.mini)
                            .frame(width: 12, height: 12)
                            .fixedSize()
                            .opacity(tabState.isLoading ? 1 : 0)
                    } else {
                        HStack(spacing: 4) {
                            Image(systemName: "clock")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(tabState.lastQueryDuration.map { formattedDuration($0) } ?? "0ms")
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .frame(minWidth: 260, alignment: .center)
        .padding(.horizontal, 12)
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
