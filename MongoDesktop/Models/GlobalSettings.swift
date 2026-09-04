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

    /// Polling interval (seconds) for real-time performance monitoring (default: 1.0s).
    @Published var performancePollingInterval: Double {
        didSet {
            defaults.set(performancePollingInterval, forKey: Self.performancePollingIntervalKey)
        }
    }

    var displayTimeZone: TimeZone {
        TimeZone(identifier: displayTimeZoneId) ?? .current
    }

    private static let displayTimeZoneIdKey = "displayTimeZoneId"
    private static let performancePollingIntervalKey = "performancePollingInterval"
    private let defaults = UserDefaults.standard

    private init() {
        if let saved = defaults.string(forKey: Self.displayTimeZoneIdKey), !saved.isEmpty {
            displayTimeZoneId = saved
        } else {
            displayTimeZoneId = TimeZone.current.identifier
        }

        let savedInterval = defaults.double(forKey: Self.performancePollingIntervalKey)
        if savedInterval > 0 {
            performancePollingInterval = savedInterval
        } else {
            performancePollingInterval = 1.0
        }
    }
}
