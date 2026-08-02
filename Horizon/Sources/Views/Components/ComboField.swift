import SwiftUI
import MapKit

/// Live map-place autocomplete backing for `ComboField` (opt-in via `mapSearch`).
/// Wraps `MKLocalSearchCompleter` so typing a location surfaces real places.
@MainActor
final class MapSearchModel: NSObject, ObservableObject, MKLocalSearchCompleterDelegate {
    /// A Sendable snapshot of a completion (MKLocalSearchCompletion isn't Sendable).
    struct Place: Hashable { let title: String; let subtitle: String }

    @Published var results: [Place] = []
    private let completer = MKLocalSearchCompleter()

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = [.address, .pointOfInterest]
    }

    func update(_ query: String) {
        let t = query.trimmingCharacters(in: .whitespaces)
        guard t.count >= 2 else { results = []; return }
        completer.queryFragment = t
    }

    func clear() { results = []; completer.queryFragment = "" }

    // MKLocalSearchCompleter always calls its delegate on the main thread.
    nonisolated func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        MainActor.assumeIsolated {
            // Use the stored completer (same object) so the non-Sendable parameter
            // isn't captured across the isolation boundary.
            self.results = self.completer.results.prefix(6).map { Place(title: $0.title, subtitle: $0.subtitle) }
        }
    }
    nonisolated func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        MainActor.assumeIsolated { self.results = [] }
    }
}

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
    /// When true, live map-place suggestions (MapKit) are merged in below the
    /// saved options, so typing surfaces real destinations/addresses.
    var mapSearch: Bool = false
    var onPick: (Option) -> Void = { _ in }
    var onAdd: (String) -> Void = { _ in }

    @FocusState private var focused: Bool
    @StateObject private var mapModel = MapSearchModel()
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
            .onChange(of: text) { _, q in
                // Only while the user is actively typing — avoids repopulating
                // suggestions right after a pick sets the text programmatically.
                if mapSearch, focused { mapModel.update(q) }
            }

        ForEach(matches) { opt in
            Button { pick(opt) } label: {
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
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            // The first tap in a focused Form field often only dismisses the
            // keyboard and never fires the Button — commit via a simultaneous
            // gesture so the selection always lands.
            .simultaneousGesture(TapGesture().onEnded { pick(opt) })
        }

        // Live map places (opt-in). A saved option with the same name wins, so we
        // hide a map row that duplicates one already shown above.
        if mapSearch, focused || active {
            let shownNames = Set(matches.map { $0.name.lowercased() })
            let places = mapModel.results.filter { !shownNames.contains($0.title.lowercased()) }
            ForEach(Array(places.enumerated()), id: \.offset) { _, place in
                Button { pickMap(place) } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "mappin.and.ellipse")
                            .foregroundStyle(Theme.Colors.brand).frame(width: 20)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(place.title).font(.subheadline.weight(.medium)).foregroundStyle(.primary)
                            if !place.subtitle.isEmpty {
                                Text(place.subtitle).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Image(systemName: "arrow.up.left").font(.caption2).foregroundStyle(.tertiary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .simultaneousGesture(TapGesture().onEnded { pickMap(place) })
            }
        }

        if showAdd {
            Button { add() } label: {
                Label("Add \u{201C}\(trimmed)\u{201D}", systemImage: "plus.circle.fill")
                    .foregroundStyle(Theme.Colors.brand)
                    .contentShape(Rectangle())
            }
            .simultaneousGesture(TapGesture().onEnded { add() })
        }
    }

    /// Picking a live map place fills the field with its name and treats it as a
    /// new value (find-or-create), matching the "Add …" flow.
    private func pickMap(_ place: MapSearchModel.Place) {
        let value = place.title.trimmingCharacters(in: .whitespaces)
        guard !value.isEmpty else { return }
        addedValue = value
        text = value
        mapModel.clear()
        onAdd(value)
        focused = false
    }

    private func pick(_ opt: Option) {
        text = opt.name
        onPick(opt)
        focused = false
    }

    private func add() {
        let value = trimmed
        // The Button action and the simultaneous gesture can both fire on one
        // tap; bail if we already committed this value so onAdd runs only once
        // (double-adding would create duplicate stores).
        guard !value.isEmpty, addedValue?.caseInsensitiveCompare(value) != .orderedSame else { return }
        addedValue = value
        text = value
        onAdd(value)
        focused = false
    }
}
