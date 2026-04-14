import SwiftUI

// MARK: - Database Tab Environment

private struct AddDatabaseTabKey: EnvironmentKey {
    static let defaultValue: () -> Void = {}
}

struct DatabaseTabItem: Identifiable, Hashable {
    let id: UUID
    let title: String
}

struct DatabaseTabContext {
    let tabs: [DatabaseTabItem]
    let selectedId: UUID?
    let select: (UUID) -> Void
    let close: (UUID) -> Void
    let add: () -> Void
    let open: (String, String) -> Void
}

private struct DatabaseTabContextKey: EnvironmentKey {
    static let defaultValue: DatabaseTabContext? = nil
}

extension EnvironmentValues {
    var addDatabaseTab: () -> Void {
        get { self[AddDatabaseTabKey.self] }
        set { self[AddDatabaseTabKey.self] = newValue }
    }

    var databaseTabContext: DatabaseTabContext? {
        get { self[DatabaseTabContextKey.self] }
        set { self[DatabaseTabContextKey.self] = newValue }
    }
}
