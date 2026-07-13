import SwiftUI

/// Multi-select people field: shows chosen travelers as removable chips, with a
/// type-to-search field over the family roster and an "Add …" row that creates a
/// new reusable person. Stores plain names (Trip.travelers is [String]).
struct TravelerField: View {
    @Binding var selected: [String]
    let members: [FamilyMember]
    /// Create a new person; returns the stored name (or nil on failure).
    var onCreate: (String) async -> String?

    @State private var query = ""
    @FocusState private var focused: Bool

    private var trimmed: String { query.trimmingCharacters(in: .whitespaces) }

    private func avatarURL(for name: String) -> String? {
        members.first { $0.name == name }?.avatarURL
    }

    private var suggestions: [FamilyMember] {
        guard focused else { return [] }
        let q = trimmed.lowercased()
        return members
            .filter { !selected.contains($0.name) }
            .filter { q.isEmpty || $0.name.lowercased().contains(q) }
            .prefix(8).map { $0 }
    }

    private var showAdd: Bool {
        focused && !trimmed.isEmpty &&
        !members.contains { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame } &&
        !selected.contains { $0.caseInsensitiveCompare(trimmed) == .orderedSame }
    }

    var body: some View {
        if !selected.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(selected, id: \.self) { name in
                        HStack(spacing: 4) {
                            PersonAvatar(name: name, avatarURL: avatarURL(for: name), size: 20)
                            Text(name).font(.subheadline)
                            Button { selected.removeAll { $0 == name } } label: {
                                Image(systemName: "xmark.circle.fill").font(.caption)
                            }
                            .buttonStyle(.plain).foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(Theme.Colors.brand.opacity(0.12), in: Capsule())
                    }
                }
            }
        }

        TextField("Add a traveler", text: $query)
            .focused($focused)
            .autocorrectionDisabled()

        ForEach(suggestions) { member in
            Button {
                selected.append(member.name); query = ""
            } label: {
                HStack(spacing: 10) {
                    PersonAvatar(name: member.name, avatarURL: member.avatarURL, size: 22)
                    Text(member.name).font(.subheadline.weight(.medium)).foregroundStyle(.primary)
                    Spacer()
                    Image(systemName: "plus").font(.caption2).foregroundStyle(.tertiary)
                }
            }
            .buttonStyle(.plain)
        }

        if showAdd {
            Button {
                let name = trimmed
                Task {
                    if let created = await onCreate(name), !selected.contains(created) {
                        selected.append(created)
                    }
                    query = ""
                }
            } label: {
                Label("Add \u{201C}\(trimmed)\u{201D} as a new person", systemImage: "person.badge.plus")
                    .foregroundStyle(Theme.Colors.brand)
            }
        }
    }
}
