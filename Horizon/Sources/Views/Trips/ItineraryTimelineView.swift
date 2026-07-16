import SwiftUI

/// What the activity editor opens with — a new activity on a default date, or an
/// existing one (with its parent day row) to edit.
struct ItineraryEditContext: Identifiable {
    let id = UUID()
    let activity: ItineraryActivity?
    let fromDayID: UUID?
    let date: Date
}

/// Infers an activity type icon + color from its title, so existing activities
/// get sensible visuals with no extra data entry.
enum ItineraryStyle {
    static func on(_ title: String) -> (icon: String, color: Color) {
        let t = title.lowercased()
        func any(_ words: [String]) -> Bool { words.contains { t.contains($0) } }
        if any(["flight", "fly", "airport", "depart", "arrive", "plane", "boarding"]) { return ("airplane", .blue) }
        if any(["drive", "road", "car ", "gas", "fuel", "parking"]) { return ("car.fill", .teal) }
        if any(["train", "rail"]) { return ("tram.fill", .teal) }
        if any(["ferry", "boat", "cruise"]) { return ("ferry.fill", .teal) }
        if any(["check-in", "check in", "checkin", "check-out", "checkout", "check out",
                "hotel", "lodging", "tent", "camp", "cabin", "airbnb", "room", "arrive at"]) { return ("bed.double.fill", .indigo) }
        if any(["breakfast", "brunch", "lunch", "dinner", "eat", "food", "restaurant",
                "cafe", "coffee", "meal", "drinks", "bar", "snack"]) { return ("fork.knife", .orange) }
        if any(["hike", "trail", "walk", "beach", "surf", "kayak", "swim", "explore",
                "sightsee", "tour", "visit", "museum", "park", "photo"]) { return ("figure.hiking", .green) }
        if any(["pack", "unpack", "load", "gear"]) { return ("bag.fill", .brown) }
        if any(["charge", "battery", "power"]) { return ("bolt.fill", .yellow) }
        return ("mappin.and.ellipse", Theme.Colors.brand)
    }
}

/// One calendar day of the itinerary: a header (Day N · weekday) with its
/// activities beneath in a connected timeline — the pattern used by TripIt /
/// Wanderlog. Each activity shows a type icon; drag one onto another to reorder.
struct ItineraryDayTimeline: View {
    let group: ItineraryDayGroup
    let dayNumber: Int?
    let onTap: (ItineraryEntry) -> Void
    let onDelete: (ItineraryEntry) -> Void
    /// (draggedActivityIDs, targetEntry) — drop the dragged item before target.
    let onReorder: ([String], ItineraryEntry) -> Void

    @State private var dropTargetID: UUID?
    private let rail = Color.secondary.opacity(0.28)

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                if let dayNumber {
                    Text("Day \(dayNumber)")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Theme.Colors.brand)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Theme.Colors.brand.opacity(0.15), in: Capsule())
                }
                Text(group.date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()))
                    .font(.subheadline.weight(.semibold))
                Spacer()
            }

            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(group.entries.enumerated()), id: \.element.id) { idx, entry in
                    row(entry, isFirst: idx == 0, isLast: idx == group.entries.count - 1)
                        .contentShape(Rectangle())
                        .background(dropTargetID == entry.id ? Theme.Colors.brand.opacity(0.10) : .clear,
                                    in: RoundedRectangle(cornerRadius: 8))
                        .onTapGesture { onTap(entry) }
                        .draggable(entry.activity.id.uuidString)
                        .dropDestination(for: String.self) { ids, _ in
                            onReorder(ids, entry); return true
                        } isTargeted: { dropTargetID = $0 ? entry.id : nil }
                        .contextMenu {
                            Button("Edit", systemImage: "pencil") { onTap(entry) }
                            Button("Delete", systemImage: "trash", role: .destructive) { onDelete(entry) }
                        }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 14))
    }

    private func row(_ entry: ItineraryEntry, isFirst: Bool, isLast: Bool) -> some View {
        let style = ItineraryStyle.on(entry.activity.title)
        let timed = ItineraryTime.display(entry.activity.time)
        return HStack(alignment: .top, spacing: 10) {
            Text(timed ?? "All day")
                .font(.caption.weight(.semibold).monospacedDigit())
                .foregroundStyle(timed != nil ? Theme.Colors.brand : .secondary)
                .frame(width: 62, alignment: .trailing)
                .padding(.top, 7)

            // Type-icon badge with a rail connecting it to the neighbours.
            VStack(spacing: 0) {
                Rectangle().fill(rail).frame(width: 2, height: 7).opacity(isFirst ? 0 : 1)
                ZStack {
                    Circle().fill(style.color.opacity(0.16)).frame(width: 28, height: 28)
                    Image(systemName: style.icon).font(.caption2).foregroundStyle(style.color)
                }
                Rectangle().fill(rail).frame(width: 2).frame(maxHeight: .infinity).opacity(isLast ? 0 : 1)
            }
            .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.activity.title).font(.subheadline.weight(.medium)).foregroundStyle(.primary)
                if let loc = entry.activity.locationName?.nilIfBlank {
                    Label(loc, systemImage: "mappin.and.ellipse")
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                if let notes = entry.activity.notes?.nilIfBlank {
                    Text(notes).font(.caption2).foregroundStyle(.tertiary).lineLimit(2)
                }
            }
            .padding(.top, 6)
            .padding(.bottom, isLast ? 0 : 16)

            Spacer(minLength: 0)
        }
    }
}

/// Add / edit a single itinerary activity: a date + (optionally) a time, title,
/// location, and notes. Time is on by default — it's an itinerary. The store
/// places it on the right day automatically (find-or-create).
struct ItineraryActivityEditView: View {
    let store: TripDetailStore
    let activity: ItineraryActivity?
    let fromDayID: UUID?
    @Environment(\.dismiss) private var dismiss

    @State private var title: String
    @State private var date: Date
    @State private var hasTime: Bool
    @State private var time: Date
    @State private var location: String
    @State private var notes: String

    init(store: TripDetailStore, activity: ItineraryActivity?, fromDayID: UUID?, initialDate: Date) {
        self.store = store; self.activity = activity; self.fromDayID = fromDayID
        _title = State(initialValue: activity?.title ?? "")
        _date = State(initialValue: initialDate)
        let parsed = ItineraryTime.parse(activity?.time)
        // New activities default to timed (it's an itinerary); editing reflects
        // whatever the activity already had.
        _hasTime = State(initialValue: activity == nil ? true : (parsed != nil))
        let nine = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: Date()) ?? Date()
        _time = State(initialValue: parsed ?? nine)
        _location = State(initialValue: activity?.locationName ?? "")
        _notes = State(initialValue: activity?.notes ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Activity (e.g. Check-in, Drive to site)", text: $title)
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                    Toggle("Set a time", isOn: $hasTime.animation())
                    if hasTime {
                        DatePicker("Time", selection: $time, displayedComponents: .hourAndMinute)
                    }
                }
                Section {
                    TextField("Location (optional)", text: $location)
                    TextField("Notes (optional)", text: $notes, axis: .vertical).lineLimit(1...4)
                }
                if activity != nil, let dayID = fromDayID, let existing = activity {
                    Section {
                        Button("Delete activity", role: .destructive) {
                            Task { await store.deleteActivity(id: existing.id, fromDayID: dayID); dismiss() }
                        }
                    }
                }
            }
            .navigationTitle(activity == nil ? "New Activity" : "Edit Activity")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await save() } }
                        .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private func save() async {
        let updated = ItineraryActivity(
            id: activity?.id ?? UUID(),
            time: hasTime ? ItineraryTime.format(time) : nil,
            title: title.trimmingCharacters(in: .whitespaces),
            locationName: location.nilIfBlank,
            mapsURL: activity?.mapsURL,
            notes: notes.nilIfBlank,
            done: activity?.done,
            reservationID: activity?.reservationID,
            sort: activity?.sort)
        await store.upsertActivity(updated, onDate: date, fromDayID: fromDayID)
        dismiss()
    }
}
