import Foundation

// MARK: - GlobalSettings (shared across windows)

final class GlobalSettings: ObservableObject {
    static let shared = GlobalSettings()

    /// Timezone used to display date fields in the UI (default: local timezone).
    @Published var displayTimeZone: TimeZone = .current

    private init() {}
}
