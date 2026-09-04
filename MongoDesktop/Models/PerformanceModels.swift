import Foundation

// MARK: - Performance Models

struct OperationMetrics: Equatable {
    var insert: Double = 0
    var query: Double = 0
    var update: Double = 0
    var delete: Double = 0
    var command: Double = 0
    var getmore: Double = 0

    var total: Double {
        insert + query + update + delete + command + getmore
    }
}

struct NetworkMetrics: Equatable {
    var bytesInRate: Double = 0   // bytes per second
    var bytesOutRate: Double = 0  // bytes per second
    var connections: Int = 0      // current connection count
}

struct MemoryMetrics: Equatable {
    var virtualMB: Double = 0
    var residentMB: Double = 0
}

struct HottestCollection: Identifiable, Equatable {
    var id: String { name }
    let name: String
    let count: Int64
    let percent: Double
}

struct SlowestOp: Identifiable, Equatable {
    let id = UUID()
    let opType: String
    let ns: String
    let durationMs: Double

    static var none: SlowestOp {
        SlowestOp(opType: "NONE", ns: "", durationMs: 0)
    }
}

struct PerformanceSnapshot: Identifiable, Equatable {
    let id = UUID()
    let timestamp: Date
    let operations: OperationMetrics
    let network: NetworkMetrics
    let memory: MemoryMetrics
    let hottestCollections: [HottestCollection]
    let slowestOps: [SlowestOp]
}
