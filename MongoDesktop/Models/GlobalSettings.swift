import Foundation

// MARK: - GlobalSettings (shared across windows)

@MainActor
final class GlobalSettings: ObservableObject {
    static let shared = GlobalSettings()

    /// Timezone identifier used to display date fields in the UI (default: local timezone).
    @Published var displayTimeZoneId: String {
        didSet {
            defaults.set(displayTimeZoneId, forKey: Self.displayTimeZoneIdKey)
        }
    }

    var displayTimeZone: TimeZone {
        TimeZone(identifier: displayTimeZoneId) ?? .current
    }

    private static let displayTimeZoneIdKey = "displayTimeZoneId"
    private let defaults = UserDefaults.standard

    private init() {
        if let saved = defaults.string(forKey: Self.displayTimeZoneIdKey), !saved.isEmpty {
            displayTimeZoneId = saved
        } else {
            displayTimeZoneId = TimeZone.current.identifier
        }
    }
}
