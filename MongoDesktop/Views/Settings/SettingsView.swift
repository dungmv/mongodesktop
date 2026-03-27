import SwiftUI

// MARK: - SettingsView

struct SettingsView: View {
    @EnvironmentObject private var globalSettings: GlobalSettings
    @State private var searchText: String = ""

    private var filteredTimeZoneIds: [String] {
        let ids = TimeZone.knownTimeZoneIdentifiers
        if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return sortedTimeZoneIds(ids)
        }
        let needle = searchText.lowercased()
        let filtered = ids.filter { id in
            id.lowercased().contains(needle) ||
            timeZoneDisplayName(for: id).lowercased().contains(needle)
        }
        return sortedTimeZoneIds(filtered)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Timezone")
                .font(.headline)

            Text("Used to display all Date fields in the app.")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Current")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(timeZoneDisplayName(for: globalSettings.displayTimeZoneId))
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                }
                Spacer()
                Button("Use System Timezone") {
                    globalSettings.displayTimeZoneId = TimeZone.current.identifier
                }
            }

            List(filteredTimeZoneIds, id: \.self) { id in
                Button {
                    globalSettings.displayTimeZoneId = id
                } label: {
                    HStack(spacing: 8) {
                        Text(timeZoneDisplayName(for: id))
                            .font(.system(.body, design: .monospaced))
                        Spacer()
                        if id == globalSettings.displayTimeZoneId {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .searchable(text: $searchText, prompt: "Search timezone")

            Text("Preview: \(exampleDateString())")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(minWidth: 520, minHeight: 520)
    }

    private func exampleDateString() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssXXXXX"
        formatter.timeZone = globalSettings.displayTimeZone
        return formatter.string(from: Date())
    }

    private func sortedTimeZoneIds(_ ids: [String]) -> [String] {
        let now = Date()
        return ids.sorted { lhs, rhs in
            let ltz = TimeZone(identifier: lhs)
            let rtz = TimeZone(identifier: rhs)
            let lo = ltz?.secondsFromGMT(for: now) ?? 0
            let ro = rtz?.secondsFromGMT(for: now) ?? 0
            if lo != ro { return lo < ro }
            return lhs.localizedCaseInsensitiveCompare(rhs) == .orderedAscending
        }
    }

    private func timeZoneDisplayName(for id: String) -> String {
        guard let tz = TimeZone(identifier: id) else { return id }
        let now = Date()
        let offset = offsetString(seconds: tz.secondsFromGMT(for: now))
        let abbr = tz.abbreviation(for: now)
        if let abbr {
            return "\(offset) \(abbr)  \(id)"
        }
        return "\(offset)  \(id)"
    }

    private func offsetString(seconds: Int) -> String {
        let sign = seconds >= 0 ? "+" : "-"
        let total = abs(seconds)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        return String(format: "GMT%@%02d:%02d", sign, hours, minutes)
    }
}
