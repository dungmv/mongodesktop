import SwiftUI

// MARK: - PerformanceView

struct PerformanceView: View {
    @EnvironmentObject private var sessionViewModel: DatabaseSessionViewModel
    @StateObject private var viewModel = PerformanceViewModel()

    init() {}

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            Divider()

            if let error = viewModel.lastError {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.yellow)
                        .font(.body)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Không thể lấy thống kê máy chủ thời gian thực")
                            .font(.subheadline.weight(.semibold))
                        Text(error)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                        Text("Lưu ý: MongoDB yêu cầu quyền 'clusterMonitor' hoặc quyền admin để chạy các lệnh thống kê máy chủ (serverStatus, top, currentOp).")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    Spacer()
                    Button("Thử lại") {
                        Task { await viewModel.pollMetrics() }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.yellow.opacity(0.1))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.yellow.opacity(0.3), lineWidth: 1)
                )
                .padding(.horizontal, 16)
                .padding(.top, 10)
            }

            ScrollView(.vertical, showsIndicators: true) {
                HStack(alignment: .top, spacing: 16) {
                    // Left Column: Charts
                    VStack(spacing: 16) {
                        operationsCard
                        networkCard
                        memoryCard
                    }
                    .frame(maxWidth: .infinity)

                    // Right Column: Hottest Collections & Slowest Operations
                    VStack(spacing: 16) {
                        hottestCollectionsCard
                        slowestOperationsCard
                    }
                    .frame(width: 320)
                }
                .padding(16)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            viewModel.startMonitoring(database: sessionViewModel.selectedDatabase)
        }
        .onChange(of: sessionViewModel.selectedDatabase) { newDb in
            viewModel.startMonitoring(database: newDb)
        }
        .onDisappear {
            viewModel.stopMonitoring()
        }
    }

    // MARK: - Header Bar

    private var headerBar: some View {
        HStack(spacing: 12) {
            // Pause / Resume Button
            Button(action: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    viewModel.togglePause()
                }
            }) {
                HStack(spacing: 6) {
                    Image(systemName: viewModel.isPaused ? "play.fill" : "pause.fill")
                        .font(.caption)
                    Text(viewModel.isPaused ? "Resume" : "Pause")
                        .font(.subheadline.weight(.medium))
                }
                .padding(.horizontal, 4)
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)

            // Current Time Badge
            HStack(spacing: 5) {
                Image(systemName: "clock")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(viewModel.currentTimeString)
                    .font(.system(.subheadline, design: .monospaced))
                    .foregroundStyle(.primary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(Color(nsColor: .separatorColor).opacity(0.5), lineWidth: 1)
            )

            // Polling Interval Setting
            Menu {
                Text("Sample Interval").font(.headline)
                Divider()
                ForEach([1.0, 2.0, 3.0, 5.0, 10.0], id: \.self) { interval in
                    Button(action: {
                        viewModel.changeRefreshInterval(interval)
                    }) {
                        HStack {
                            Text("\(Int(interval))s")
                            if viewModel.refreshInterval == interval {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "timer")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text("\(Int(viewModel.refreshInterval))s")
                        .font(.system(.subheadline, design: .monospaced))
                    Image(systemName: "chevron.down")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color(nsColor: .controlBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(Color(nsColor: .separatorColor).opacity(0.5), lineWidth: 1)
                )
            }
            .menuStyle(.borderlessButton)
            .help("Change sampling interval")

            Spacer()

            // Database / Connection Info
            if !sessionViewModel.connectionName.isEmpty {
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 8, height: 8)
                    Text(sessionViewModel.connectionName)
                        .font(.headline)
                        .lineLimit(1)
                }
                .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Operations Card

    private var operationsCard: some View {
        let current = viewModel.currentSnapshot?.operations ?? OperationMetrics()
        let insertValues = viewModel.snapshots.map(\.operations.insert)
        let queryValues = viewModel.snapshots.map(\.operations.query)
        let updateValues = viewModel.snapshots.map(\.operations.update)
        let deleteValues = viewModel.snapshots.map(\.operations.delete)
        let commandValues = viewModel.snapshots.map(\.operations.command)
        let getmoreValues = viewModel.snapshots.map(\.operations.getmore)

        let allValues = insertValues + queryValues + updateValues + deleteValues + commandValues + getmoreValues
        let maxVal = max(4.0, (allValues.max() ?? 0) * 1.2)

        return cardContainer(title: "OPERATIONS") {
            VStack(alignment: .leading, spacing: 10) {
                PerformanceChartView(
                    series: [
                        ChartSeries(name: "INSERT", color: .green, values: insertValues),
                        ChartSeries(name: "QUERY", color: .cyan, values: queryValues),
                        ChartSeries(name: "UPDATE", color: .blue, values: updateValues),
                        ChartSeries(name: "DELETE", color: .red, values: deleteValues),
                        ChartSeries(name: "COMMAND", color: .purple, values: commandValues),
                        ChartSeries(name: "GETMORE", color: .orange, values: getmoreValues)
                    ],
                    yAxisLabel: "\(formatOps(maxVal)) ops",
                    maxValueOverride: maxVal
                )
                .frame(height: 120)

                // Metric Counters Legend
                HStack(spacing: 0) {
                    metricItem(color: .green, label: "INSERT", value: formatOps(current.insert))
                    metricItem(color: .cyan, label: "QUERY", value: formatOps(current.query))
                    metricItem(color: .blue, label: "UPDATE", value: formatOps(current.update))
                    metricItem(color: .red, label: "DELETE", value: formatOps(current.delete))
                    metricItem(color: .purple, label: "COMMAND", value: formatOps(current.command))
                    metricItem(color: .orange, label: "GETMORE", value: formatOps(current.getmore))
                }
            }
        }
    }

    // MARK: - Network Card

    private var networkCard: some View {
        let current = viewModel.currentSnapshot?.network ?? NetworkMetrics()
        let bytesInValues = viewModel.snapshots.map(\.network.bytesInRate)
        let bytesOutValues = viewModel.snapshots.map(\.network.bytesOutRate)
        let connValues = viewModel.snapshots.map { Double($0.network.connections) }

        let allBytes = bytesInValues + bytesOutValues
        let maxBytes = max(1024.0, (allBytes.max() ?? 0) * 1.2)
        let maxConn = max(5.0, (connValues.max() ?? 0) * 1.2)

        return cardContainer(title: "NETWORK") {
            VStack(alignment: .leading, spacing: 10) {
                PerformanceChartView(
                    series: [
                        ChartSeries(name: "BYTESIN", color: .green, values: bytesInValues),
                        ChartSeries(name: "BYTESOUT", color: .cyan, values: bytesOutValues)
                    ],
                    secondarySeries: ChartSeries(name: "CONNECTIONS", color: .blue, values: connValues),
                    yAxisLabel: formatBytesRate(maxBytes),
                    secondaryYAxisLabel: "\(Int(maxConn)) conn",
                    maxValueOverride: maxBytes
                )
                .frame(height: 120)

                // Metric Counters Legend
                HStack(spacing: 0) {
                    metricItem(color: .green, label: "BYTESIN", value: formatBytesRate(current.bytesInRate))
                    metricItem(color: .cyan, label: "BYTESOUT", value: formatBytesRate(current.bytesOutRate))
                    metricItem(color: .blue, label: "CONNECTIONS", value: "\(current.connections)")
                    Spacer()
                }
            }
        }
    }

    // MARK: - Memory Card

    private var memoryCard: some View {
        let current = viewModel.currentSnapshot?.memory ?? MemoryMetrics()
        let virtualValues = viewModel.snapshots.map(\.memory.virtualMB)
        let residentValues = viewModel.snapshots.map(\.memory.residentMB)

        let allMem = virtualValues + residentValues
        let maxMem = max(512.0, (allMem.max() ?? 0) * 1.2)

        return cardContainer(title: "MEMORY") {
            VStack(alignment: .leading, spacing: 10) {
                PerformanceChartView(
                    series: [
                        ChartSeries(name: "VIRTUAL", color: .green, values: virtualValues),
                        ChartSeries(name: "RESIDENT", color: .cyan, values: residentValues)
                    ],
                    yAxisLabel: formatMemoryMB(maxMem),
                    maxValueOverride: maxMem
                )
                .frame(height: 120)

                // Metric Counters Legend
                HStack(spacing: 0) {
                    metricItem(color: .green, label: "VIRTUAL", value: formatMemoryMB(current.virtualMB))
                    metricItem(color: .cyan, label: "RESIDENT", value: formatMemoryMB(current.residentMB))
                    Spacer()
                }
            }
        }
    }

    // MARK: - Hottest Collections Card

    private var hottestCollectionsCard: some View {
        let collections = viewModel.currentSnapshot?.hottestCollections ?? []

        return cardContainer(title: "HOTTEST COLLECTIONS") {
            VStack(alignment: .leading, spacing: 8) {
                if collections.isEmpty {
                    HStack {
                        Spacer()
                        VStack(spacing: 6) {
                            Image(systemName: "checkmark")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(.secondary)
                            Text("No Hot Collections")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 24)
                        Spacer()
                    }
                } else {
                    ForEach(collections) { item in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(item.name)
                                    .font(.subheadline.weight(.medium))
                                    .lineLimit(1)
                                Spacer()
                                Text(String(format: "%.1f%%", item.percent))
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                            ProgressView(value: min(1.0, max(0.0, item.percent / 100.0)))
                                .progressViewStyle(.linear)
                                .tint(.orange)
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
            .frame(minHeight: 100)
        }
    }

    // MARK: - Slowest Operations Card

    private var slowestOperationsCard: some View {
        let ops = viewModel.currentSnapshot?.slowestOps ?? [
            .none, .none, .none, .none, .none
        ]

        return cardContainer(title: "SLOWEST OPERATIONS") {
            VStack(spacing: 6) {
                ForEach(Array(ops.enumerated()), id: \.offset) { index, item in
                    HStack(spacing: 8) {
                        // Badge Tag
                        Text(item.opType)
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(
                                RoundedRectangle(cornerRadius: 4, style: .continuous)
                                    .fill(item.opType == "NONE" ? Color(nsColor: .quaternaryLabelColor) : Color.accentColor.opacity(0.15))
                            )
                            .foregroundStyle(item.opType == "NONE" ? .secondary : Color.accentColor)

                        // Operation NS / target
                        if !item.ns.isEmpty {
                            Text(item.ns)
                                .font(.caption)
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                        }

                        Spacer()

                        // Duration
                        Text("\(Int(item.durationMs)) ms")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color(nsColor: .textBackgroundColor).opacity(0.35))
                    )
                }
            }
        }
    }

    // MARK: - Reusable UI Components

    private func cardContainer<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)

            content()
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color(nsColor: .separatorColor).opacity(0.5), lineWidth: 1)
        )
    }

    private func metricItem(color: Color, label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 5) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(color)
                    .frame(width: 8, height: 8)
                Text(label)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            Text(value)
                .font(.system(.subheadline, design: .monospaced).weight(.semibold))
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Formatters

    private func formatOps(_ ops: Double) -> String {
        if ops < 10 {
            return String(format: "%.1f", ops)
        } else {
            return "\(Int(ops))"
        }
    }

    private func formatBytesRate(_ bytes: Double) -> String {
        if bytes < 1024 {
            return "\(Int(bytes)) B"
        } else if bytes < 1024 * 1024 {
            return String(format: "%.0f KB", bytes / 1024.0)
        } else if bytes < 1024 * 1024 * 1024 {
            return String(format: "%.1f MB", bytes / (1024.0 * 1024.0))
        } else {
            return String(format: "%.2f GB", bytes / (1024.0 * 1024.0 * 1024.0))
        }
    }

    private func formatMemoryMB(_ mb: Double) -> String {
        if mb < 1024 {
            return String(format: "%.0f MB", mb)
        } else {
            return String(format: "%.2f GB", mb / 1024.0)
        }
    }
}
