import SwiftUI

// MARK: - DatabasePickerButton

struct DatabasePickerButton: View {
    @EnvironmentObject private var sessionViewModel: DatabaseSessionViewModel
    @State private var isPresented = false
    @State private var searchText = ""

    private var filtered: [String] {
        searchText.isEmpty
            ? sessionViewModel.databases
            : sessionViewModel.databases.filter { $0.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        Button(action: { isPresented.toggle() }) {
            Image(systemName: "cylinder.split.1x2")
        }
        .help("Chọn/Đổi database")
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            DatabasePickerPopover(
                databases: filtered,
                selected: sessionViewModel.selectedDatabase,
                searchText: $searchText,
                isPresented: $isPresented,
                onSelect: { db in
                    sessionViewModel.selectDatabase(db)
                }
            )
        }
    }
}

// MARK: - DatabasePickerPopover

struct DatabasePickerPopover: View {
    let databases: [String]
    let selected: String?
    @Binding var searchText: String
    @Binding var isPresented: Bool
    let onSelect: (String) -> Void
    
    @State private var pendingDatabase: String? = nil

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .font(.callout)
                TextField("Tìm database...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.callout)
                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            Divider()

            if databases.isEmpty {
                Text(searchText.isEmpty ? "Không có database" : "Không tìm thấy")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(20)
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(databases, id: \.self) { db in
                            DatabasePickerRow(
                                name: db,
                                isSelected: selected == db,
                                onTap: { 
                                    pendingDatabase = db
                                    isPresented = false
                                }
                            )
                        }
                    }
                    .padding(6)
                }
                .frame(maxHeight: 260)
            }
        }
        .frame(minWidth: 220)
        .background(.regularMaterial)
        .onDisappear {
            if let db = pendingDatabase {
                DispatchQueue.main.async {
                    onSelect(db)
                }
            }
        }
    }
}

// MARK: - DatabasePickerRow

struct DatabasePickerRow: View {
    let name: String
    let isSelected: Bool
    let onTap: () -> Void
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "cylinder.split.1x2")
                .font(.caption)
                .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                .frame(width: 16)
            Text(name)
                .font(.system(.body, design: .rounded))
                .foregroundStyle(.primary)
            Spacer()
            if isSelected {
                Image(systemName: "checkmark")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(isSelected
                      ? Color.accentColor.opacity(0.12)
                      : (isHovered ? Color.primary.opacity(0.06) : Color.clear))
        )
        .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .onTapGesture { onTap() }
        .onHover { isHovered = $0 }
    }
}
