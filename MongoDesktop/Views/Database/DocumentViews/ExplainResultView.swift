import SwiftUI
import SwiftBSON

// MARK: - Explain Result Model

struct ExplainResult {
    let rawDocument: BSONDocument
    let queryPlanner: BSONDocument?
    let executionStats: BSONDocument?

    // MARK: - Parsed stats

    var winningPlan: BSONDocument? {
        queryPlanner?["winningPlan"]?.documentValue
    }

    var stage: String? {
        winningPlan?["stage"]?.stringValue
    }

    var nReturned: Int? {
        if let v = executionStats?["nReturned"] { return bsonInt(v) }
        return nil
    }

    var executionTimeMillis: Int? {
        if let v = executionStats?["executionTimeMillis"] { return bsonInt(v) }
        return nil
    }

    var totalDocsExamined: Int? {
        if let v = executionStats?["totalDocsExamined"] { return bsonInt(v) }
        return nil
    }

    var totalKeysExamined: Int? {
        if let v = executionStats?["totalKeysExamined"] { return bsonInt(v) }
        return nil
    }

    var sortedInMemory: Bool? {
        executionStats?["hasSortStage"]?.boolValue
    }

    var hasIndex: Bool {
        guard let plan = winningPlan else { return false }
        return containsIndexScan(plan)
    }

    private func containsIndexScan(_ doc: BSONDocument) -> Bool {
        if let stage = doc["stage"]?.stringValue {
            if stage == "IXSCAN" || stage == "COUNT_SCAN" { return true }
        }
        if let input = doc["inputStage"]?.documentValue {
            return containsIndexScan(input)
        }
        if let inputs = doc["inputStages"]?.arrayValue {
            return inputs.compactMap { $0.documentValue }.contains { containsIndexScan($0) }
        }
        return false
    }

    private func bsonInt(_ val: BSON) -> Int? {
        switch val {
        case .int32(let i): return Int(i)
        case .int64(let i): return Int(i)
        case .double(let d): return Int(d)
        default: return nil
        }
    }
}

// MARK: - Explain Result View

struct ExplainResultView: View {
    let result: ExplainResult
    @Binding var isPresented: Bool

    @State private var selectedTab: ExplainTab = .visualTree

    enum ExplainTab: String, CaseIterable {
        case visualTree = "Visual Tree"
        case rawOutput = "Raw Output"
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView
            Divider()

            // Content
            HStack(alignment: .top, spacing: 0) {
                // Left: tabs + tree/raw
                VStack(spacing: 0) {
                    tabPickerView
                        .padding(.horizontal, 16)
                        .padding(.top, 12)

                    Divider()
                        .padding(.top, 8)

                    switch selectedTab {
                    case .visualTree:
                        visualTreeContent
                    case .rawOutput:
                        rawOutputContent
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                Divider()

                // Right: performance summary
                querySummaryPanel
                    .frame(width: 240)
                    .padding(16)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            // Footer
            HStack {
                Spacer()
                Button("Close") { isPresented = false }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .frame(width: 780, height: 480)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Header

    private var headerView: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Explain Plan")
                    .font(.title2.weight(.semibold))
                Text("Explain provides key execution metrics that help diagnose slow queries and optimize index usage.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Button {
                isPresented = false
            } label: {
                Image(systemName: "xmark")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 10)
    }

    // MARK: - Tab Picker

    private var tabPickerView: some View {
        HStack(spacing: 0) {
            ForEach(ExplainTab.allCases, id: \.self) { tab in
                Button(action: { selectedTab = tab }) {
                    HStack(spacing: 6) {
                        Image(systemName: tab == .visualTree ? "chart.bar.doc.horizontal" : "curlybraces")
                            .font(.caption.weight(.medium))
                        Text(tab.rawValue)
                            .font(.caption.weight(.medium))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        selectedTab == tab
                            ? Color(nsColor: .controlAccentColor).opacity(0.15)
                            : Color.clear,
                        in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                    )
                    .foregroundStyle(
                        selectedTab == tab
                            ? Color.accentColor
                            : Color.secondary
                    )
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
    }

    // MARK: - Visual Tree

    private var visualTreeContent: some View {
        ScrollView([.horizontal, .vertical]) {
            VStack(alignment: .leading, spacing: 0) {
                if let plan = result.winningPlan {
                    PlanStageNodeView(stage: plan, depth: 0)
                        .padding(24)
                } else {
                    Text("No execution plan available.")
                        .foregroundStyle(.secondary)
                        .padding(24)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    // MARK: - Raw Output

    private var rawOutputContent: some View {
        ScrollView {
            Text(result.rawDocument.toExtendedJSONString())
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.primary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
        }
    }

    // MARK: - Query Performance Summary Panel

    private var querySummaryPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Query Performance Summary")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)
                .padding(.bottom, 14)

            VStack(alignment: .leading, spacing: 10) {
                summaryRow(
                    icon: "doc.text",
                    value: result.nReturned.map { "\($0)" } ?? "—",
                    label: "documents returned"
                )
                summaryRow(
                    icon: "doc.badge.ellipsis",
                    value: result.totalDocsExamined.map { "\($0)" } ?? "—",
                    label: "documents examined"
                )
                summaryRow(
                    icon: "clock",
                    value: result.executionTimeMillis.map { "\($0) ms" } ?? "—",
                    label: "execution time"
                )
                summaryRow(
                    icon: "arrow.up.arrow.down",
                    value: result.sortedInMemory == true ? "Is" : "Is not",
                    label: "sorted in memory",
                    valueStyle: result.sortedInMemory == true ? .orange : .primary
                )
                summaryRow(
                    icon: "key",
                    value: result.totalKeysExamined.map { "\($0)" } ?? "—",
                    label: "index keys examined"
                )
            }

            if !result.hasIndex {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .font(.caption)
                    Text("No index available for this query.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 14)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(nsColor: .separatorColor).opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color(nsColor: .separatorColor).opacity(0.25), lineWidth: 1)
                )
        )
    }

    private func summaryRow(
        icon: String,
        value: String,
        label: String,
        valueStyle: Color = .primary
    ) -> some View {
        HStack(alignment: .center, spacing: 8) {
            Image(systemName: icon)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(width: 14)
            Text(value)
                .font(.caption.weight(.semibold))
                .foregroundStyle(valueStyle)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Plan Stage Node

struct PlanStageNodeView: View {
    let stage: BSONDocument
    let depth: Int

    private var stageName: String {
        stage["stage"]?.stringValue ?? "UNKNOWN"
    }

    private var stageColor: Color {
        switch stageName {
        case "COLLSCAN": return .orange
        case "IXSCAN", "COUNT_SCAN": return .green
        case "FETCH": return Color.accentColor
        case "SORT", "SORT_MERGE": return .purple
        case "PROJECTION_SIMPLE", "PROJECTION_DEFAULT": return .teal
        case "LIMIT", "SKIP": return .indigo
        default: return .gray
        }
    }

    private var inputStages: [BSONDocument] {
        var stages: [BSONDocument] = []
        if let single = stage["inputStage"]?.documentValue {
            stages.append(single)
        }
        if let multi = stage["inputStages"]?.arrayValue {
            stages += multi.compactMap { $0.documentValue }
        }
        return stages
    }

    // Extract key stats for this stage node
    private var statsText: String? {
        var parts: [String] = []

        if let keyPattern = stage["keyPattern"]?.documentValue {
            let keys = keyPattern.keys.joined(separator: ", ")
            parts.append("Key: \(keys)")
        }
        if let direction = stage["direction"]?.stringValue {
            parts.append("Dir: \(direction)")
        }
        if let indexName = stage["indexName"]?.stringValue {
            parts.append("Index: \(indexName)")
        }

        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    // Extract execution count if available in explain stats
    private var nReturned: Int? {
        if let v = stage["nReturned"] {
            switch v {
            case .int32(let i): return Int(i)
            case .int64(let i): return Int(i)
            case .double(let d): return Int(d)
            default: return nil
            }
        }
        return nil
    }

    private var executionTimeMs: Int? {
        if let v = stage["executionTimeMillisEstimate"] {
            switch v {
            case .int32(let i): return Int(i)
            case .int64(let i): return Int(i)
            case .double(let d): return Int(d)
            default: return nil
            }
        }
        return nil
    }

    private var docsExamined: Int? {
        if let v = stage["docsExamined"] {
            switch v {
            case .int32(let i): return Int(i)
            case .int64(let i): return Int(i)
            case .double(let d): return Int(d)
            default: return nil
            }
        }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Connector line for child nodes
            if depth > 0 {
                HStack(spacing: 0) {
                    Spacer().frame(width: 20)
                    Rectangle()
                        .fill(Color.secondary.opacity(0.3))
                        .frame(width: 2, height: 12)
                }
            }

            // Stage card
            HStack(alignment: .top, spacing: 12) {
                // Stage color indicator
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(stageColor)
                    .frame(width: 4, height: 44)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        // Stage name badge
                        Image(systemName: "chevron.right")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(stageColor)

                        Text(stageName)
                            .font(.system(.caption, design: .monospaced).weight(.bold))
                            .foregroundStyle(stageColor)

                        Spacer()

                        // Execution time badge
                        if let ms = executionTimeMs {
                            Text("\(ms) ms")
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(stageColor.opacity(0.85), in: Circle())
                                .frame(width: 44, height: 24)
                        }
                    }

                    HStack(spacing: 12) {
                        if let n = nReturned {
                            Label("Returned \(n)", systemImage: "")
                                .labelStyle(.titleOnly)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        if let docs = docsExamined {
                            Text("Documents Examined: \(docs)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        if let _ = nReturned, let time = executionTimeMs {
                            Text("Execution Time \(time) ms")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }

                    if let stats = statsText {
                        Text(stats)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
                    .shadow(color: .black.opacity(0.07), radius: 3, x: 0, y: 1)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(stageColor.opacity(0.25), lineWidth: 1)
            )
            .frame(minWidth: 240, maxWidth: 340)

            // Children (input stages)
            if !inputStages.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(inputStages.enumerated()), id: \.offset) { _, childStage in
                        PlanStageNodeView(stage: childStage, depth: depth + 1)
                            .padding(.leading, 22)
                    }
                }
            }
        }
    }
}

// MARK: - Explain Loading View

struct ExplainLoadingView: View {
    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
                .scaleEffect(0.8)
            Text("Running explain…")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(width: 160, height: 80)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.ultraThinMaterial)
                .shadow(radius: 8)
        )
    }
}
