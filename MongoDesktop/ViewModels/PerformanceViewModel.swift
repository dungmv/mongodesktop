import Foundation
import SwiftUI
import SwiftBSON

@MainActor
final class PerformanceViewModel: ObservableObject {
    @Published var snapshots: [PerformanceSnapshot] = []
    @Published var isPaused: Bool = false
    @Published var refreshInterval: Double = 1.0
    @Published var currentTimeString: String = ""
    @Published var lastError: String? = nil
    @Published var isLoading: Bool = false
    @Published var isUsingFallbackStats: Bool = false

    var targetDatabase: String?

    private let mongoService: MongoService
    private var timerTask: Task<Void, Never>?

    // Previous raw values for delta calculation
    private var prevTimestamp: Date?
    private var prevOpcounters: [String: Double]?
    private var prevNetworkBytes: (bytesIn: Double, bytesOut: Double)?
    private var prevTopTotals: [String: Int64]?

    private let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    init(mongoService: MongoService = .shared) {
        self.mongoService = mongoService
        self.refreshInterval = GlobalSettings.shared.performancePollingInterval
        updateCurrentTime()
    }

    deinit {
        timerTask?.cancel()
    }

    var currentSnapshot: PerformanceSnapshot? {
        snapshots.last
    }

    func startMonitoring(database: String? = nil) {
        if let database, !database.isEmpty {
            self.targetDatabase = database
        }
        stopMonitoring()
        updateCurrentTime()
        timerTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                if !self.isPaused {
                    await self.pollMetrics()
                }
                self.updateCurrentTime()
                let interval = max(0.5, self.refreshInterval)
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            }
        }
    }

    func stopMonitoring() {
        timerTask?.cancel()
        timerTask = nil
    }

    func togglePause() {
        isPaused.toggle()
        updateCurrentTime()
    }

    func changeRefreshInterval(_ newInterval: Double) {
        refreshInterval = newInterval
        GlobalSettings.shared.performancePollingInterval = newInterval
        startMonitoring(database: targetDatabase)
    }

    private func updateCurrentTime() {
        currentTimeString = timeFormatter.string(from: Date())
    }

    func pollMetrics() async {
        let now = Date()
        do {
            let serverStatusDoc = try await mongoService.fetchServerStatus(database: targetDatabase)
            isUsingFallbackStats = false

            let topDoc = try? await mongoService.fetchTop()
            let currentOpsDocs = (try? await mongoService.fetchCurrentOps(database: targetDatabase)) ?? []

            let dt: Double
            if let prevTime = prevTimestamp {
                dt = max(0.2, now.timeIntervalSince(prevTime))
            } else {
                dt = refreshInterval
            }
            prevTimestamp = now

            // 1. Parse Opcounters
            var ops = OperationMetrics()
            if let opcounters = serverStatusDoc["opcounters"]?.documentValue {
                let currentInsert = extractDouble(opcounters["insert"])
                let currentQuery = extractDouble(opcounters["query"])
                let currentUpdate = extractDouble(opcounters["update"])
                let currentDelete = extractDouble(opcounters["delete"])
                let currentCommand = extractDouble(opcounters["command"])
                let currentGetmore = extractDouble(opcounters["getmore"])

                if let prev = prevOpcounters {
                    ops.insert = max(0, (currentInsert - (prev["insert"] ?? currentInsert)) / dt)
                    ops.query = max(0, (currentQuery - (prev["query"] ?? currentQuery)) / dt)
                    ops.update = max(0, (currentUpdate - (prev["update"] ?? currentUpdate)) / dt)
                    ops.delete = max(0, (currentDelete - (prev["delete"] ?? currentDelete)) / dt)
                    ops.command = max(0, (currentCommand - (prev["command"] ?? currentCommand)) / dt)
                    ops.getmore = max(0, (currentGetmore - (prev["getmore"] ?? currentGetmore)) / dt)
                }

                prevOpcounters = [
                    "insert": currentInsert,
                    "query": currentQuery,
                    "update": currentUpdate,
                    "delete": currentDelete,
                    "command": currentCommand,
                    "getmore": currentGetmore
                ]
            }

            // 2. Parse Network & Connections
            var net = NetworkMetrics()
            if let networkDoc = serverStatusDoc["network"]?.documentValue {
                let currentIn = extractDouble(networkDoc["bytesIn"])
                let currentOut = extractDouble(networkDoc["bytesOut"])

                if let prevNet = prevNetworkBytes {
                    net.bytesInRate = max(0, (currentIn - prevNet.bytesIn) / dt)
                    net.bytesOutRate = max(0, (currentOut - prevNet.bytesOut) / dt)
                }

                prevNetworkBytes = (currentIn, currentOut)
            }

            if let connectionsDoc = serverStatusDoc["connections"]?.documentValue {
                net.connections = Int(extractDouble(connectionsDoc["current"]))
            }

            // 3. Parse Memory (resident, virtual in MB)
            var mem = MemoryMetrics()
            if let memDoc = serverStatusDoc["mem"]?.documentValue {
                mem.residentMB = extractDouble(memDoc["resident"])
                mem.virtualMB = extractDouble(memDoc["virtual"])
            }

            // 4. Parse Hottest Collections from `top`
            var hottestCollections: [HottestCollection] = []
            if let topDoc, let totals = topDoc["totals"]?.documentValue {
                var currentTotals: [String: Int64] = [:]
                var deltas: [(name: String, delta: Int64)] = []

                for (key, val) in totals {
                    guard key != "note", let collectionStats = val.documentValue else { continue }
                    let totalTime = extractInt64(collectionStats["total"]?.documentValue?["time"])
                    currentTotals[key] = totalTime

                    if let prevTotals = prevTopTotals, let prevTime = prevTotals[key] {
                        let diff = max(0, totalTime - prevTime)
                        if diff > 0 {
                            deltas.append((name: key, delta: diff))
                        }
                    }
                }
                prevTopTotals = currentTotals

                deltas.sort { $0.delta > $1.delta }
                let totalDelta = Double(deltas.reduce(0) { $0 + $1.delta })
                if totalDelta > 0 {
                    hottestCollections = deltas.prefix(5).map { item in
                        let pct = (Double(item.delta) / totalDelta) * 100.0
                        return HottestCollection(name: item.name, count: item.delta, percent: pct)
                    }
                }
            }

            // 5. Parse Slowest Operations from `currentOp`
            var slowOps: [SlowestOp] = []
            for doc in currentOpsDocs {
                guard doc["active"]?.boolValue ?? true else { continue }
                let op = doc["op"]?.stringValue?.uppercased() ?? "COMMAND"
                guard op != "NONE" else { continue }
                let ns = doc["ns"]?.stringValue ?? ""
                // Skip internal system queries
                if ns.hasPrefix("local.") || ns.hasPrefix("admin.system.") || ns.hasPrefix("config.") {
                    continue
                }

                var durationMs: Double = 0
                if let microsecs = doc["microsecs_running"] {
                    durationMs = extractDouble(microsecs) / 1000.0
                } else if let secs = doc["secs_running"] {
                    durationMs = extractDouble(secs) * 1000.0
                }

                slowOps.append(SlowestOp(opType: op, ns: ns, durationMs: durationMs))
            }

            slowOps.sort { $0.durationMs > $1.durationMs }
            var finalSlowOps = Array(slowOps.prefix(5))
            while finalSlowOps.count < 5 {
                finalSlowOps.append(.none)
            }

            // Build snapshot
            let snapshot = PerformanceSnapshot(
                timestamp: now,
                operations: ops,
                network: net,
                memory: mem,
                hottestCollections: hottestCollections,
                slowestOps: finalSlowOps
            )

            snapshots.append(snapshot)
            if snapshots.count > 40 {
                snapshots.removeFirst(snapshots.count - 40)
            }
            lastError = nil
        } catch {
            #if DEBUG
            print("[Performance] serverStatus failed with error: \(error)")
            #endif
            lastError = error.localizedDescription

            // Fallback: If serverStatus is not authorized, try dbStats for memory/storage sizes
            if let db = targetDatabase, !db.isEmpty, let dbStatsDoc = try? await mongoService.fetchDbStats(database: db) {
                isUsingFallbackStats = true
                var mem = MemoryMetrics()
                let dataSize = extractDouble(dbStatsDoc["dataSize"]) / (1024 * 1024)
                let storageSize = extractDouble(dbStatsDoc["storageSize"]) / (1024 * 1024)
                mem.residentMB = storageSize
                mem.virtualMB = dataSize

                let snapshot = PerformanceSnapshot(
                    timestamp: now,
                    operations: OperationMetrics(),
                    network: NetworkMetrics(),
                    memory: mem,
                    hottestCollections: [],
                    slowestOps: [.none, .none, .none, .none, .none]
                )
                snapshots.append(snapshot)
                if snapshots.count > 40 {
                    snapshots.removeFirst(snapshots.count - 40)
                }
            }
        }
    }

    // MARK: - Helpers
    private func extractDouble(_ val: BSON?) -> Double {
        guard let val else { return 0 }
        switch val {
        case .double(let d): return d
        case .int32(let i): return Double(i)
        case .int64(let i): return Double(i)
        case .decimal128(let d): return Double(d.description) ?? 0
        default: return 0
        }
    }

    private func extractInt64(_ val: BSON?) -> Int64 {
        guard let val else { return 0 }
        switch val {
        case .int64(let i): return i
        case .int32(let i): return Int64(i)
        case .double(let d): return Int64(d)
        case .decimal128(let d): return Int64(Double(d.description) ?? 0)
        default: return 0
        }
    }
}
