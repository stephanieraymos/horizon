import SwiftUI

/// Reusable type-to-search field: a text field plus live-filtered suggestion
/// rows and an "Add …" row at the bottom — the combobox pattern used across the
/// family apps. Emits `onPick` for an existing option and `onAdd` for a new one.
/// Designed to be dropped straight into a Form `Section` (it renders sibling rows).
struct ComboField: View {
    struct Option: Identifiable, Hashable {
        var id: String
        var name: String
        var icon: String? = nil
        var subtitle: String? = nil
    }

    let placeholder: String
    @Binding var text: String
    var options: [Option]
    var allowAdd: Bool = true
    var pickIcon: String = "magnifyingglass"
    var onPick: (Option) -> Void = { _ in }
    var onAdd: (String) -> Void = { _ in }

    @FocusState private var focused: Bool

    private var trimmed: String { text.trimmingCharacters(in: .whitespaces) }

    private var matches: [Option] {
        guard focused else { return [] }
        let q = trimmed.lowercased()
        let filtered = q.isEmpty ? options : options.filter { $0.name.lowercased().contains(q) }
        return Array(filtered.prefix(8))
    }

    private var showAdd: Bool {
        focused && allowAdd && !trimmed.isEmpty &&
        !options.contains { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }
    }

    var body: some View {
        TextField(placeholder, text: $text)
            .focused($focused)
            .autocorrectionDisabled()

        ForEach(matches) { opt in
            Button {
                text = opt.name
                onPick(opt)
                focused = false
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: opt.icon ?? pickIcon)
                        .foregroundStyle(.secondary).frame(width: 20)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(opt.name).font(.subheadline.weight(.medium)).foregroundStyle(.primary)
                        if let s = opt.subtitle {
                            Text(s).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Image(systemName: "arrow.up.left").font(.caption2).foregroundStyle(.tertiary)
                }
            }
            .buttonStyle(.plain)
        }

        if showAdd {
            Button {
                let value = trimmed
                onAdd(value)
                focused = false
            } label: {
                Label("Add \u{201C}\(trimmed)\u{201D}", systemImage: "plus.circle.fill")
                    .foregroundStyle(Theme.Colors.brand)
            }
        }
    }
}
