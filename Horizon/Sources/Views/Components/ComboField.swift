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
    /// Mirrors focus but lingers briefly after focus loss so a tap on a suggestion
    /// still registers before the list collapses (the tap-drop gotcha).
    @State private var active = false
    /// The value just confirmed via "Add …", so the Add row disappears on tap —
    /// otherwise, for fields that don't add to `options` (e.g. tags), the row
    /// lingers and it looks like nothing happened.
    @State private var addedValue: String?

    private var trimmed: String { text.trimmingCharacters(in: .whitespaces) }

    // With an empty query we show the FULL list the moment the field is focused
    // (so a tap reveals everything); typing filters it down. We key off `focused`
    // directly — not the onChange-mirrored `active` — because onChange doesn't
    // reliably fire on focus-gain, which left the list hidden until the first
    // keystroke. `active` still lingers briefly after focus loss so a tap on a
    // suggestion lands before the list collapses. The typed case isn't gated on
    // focus, so tapping a filtered suggestion never drops the selection.
    private var matches: [Option] {
        let q = trimmed.lowercased()
        if q.isEmpty {
            return (focused || active) ? Array(options.sorted { $0.name < $1.name }.prefix(50)) : []
        }
        let filtered = options.filter { $0.name.lowercased().contains(q) }
        if filtered.count == 1 && filtered[0].name.caseInsensitiveCompare(trimmed) == .orderedSame { return [] }
        return Array(filtered.prefix(8))
    }

    private var showAdd: Bool {
        allowAdd && !trimmed.isEmpty &&
        !options.contains { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame } &&
        addedValue?.caseInsensitiveCompare(trimmed) != .orderedSame
    }

    var body: some View {
        TextField(placeholder, text: $text)
            .focused($focused)
            .autocorrectionDisabled()
            .onChange(of: focused) { _, isFocused in
                if isFocused { active = true }
                else {
                    // Keep the list up briefly so a tap on a row lands first.
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 250_000_000)
                        if !focused { active = false }
                    }
                }
            }

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
                addedValue = value
                onAdd(value)
                focused = false
            } label: {
                Label("Add \u{201C}\(trimmed)\u{201D}", systemImage: "plus.circle.fill")
                    .foregroundStyle(Theme.Colors.brand)
            }
        }
    }
}
