import SwiftUI

/// What the activity editor opens with — a new activity on a default date, or an
/// existing one (with its parent day row) to edit.
struct ItineraryEditContext: Identifiable {
    let id = UUID()
    let activity: ItineraryActivity?
    let fromDayID: UUID?
    let date: Date
}

/// One calendar day of the itinerary: a header (Day N · weekday) with its
/// activities beneath in a time-sorted timeline — the pattern used by TripIt /
/// Wanderlog (one day header, activities nested, chronological), instead of a
/// separate dated card per activity.
struct ItineraryDayTimeline: View {
    let group: ItineraryDayGroup
    let dayNumber: Int?
    let onTap: (ItineraryEntry) -> Void
    let onDelete: (ItineraryEntry) -> Void

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

            VStack(alignment: .leading, spacing: 14) {
                ForEach(group.entries) { entry in
                    Button { onTap(entry) } label: { row(entry) }
                        .buttonStyle(.plain)
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

    private func row(_ entry: ItineraryEntry) -> some View {
        let timed = ItineraryTime.display(entry.activity.time)
        return HStack(alignment: .top, spacing: 10) {
            Text(timed ?? "All day")
                .font(.caption.weight(.semibold).monospacedDigit())
                .foregroundStyle(timed != nil ? Theme.Colors.brand : .secondary)
                .frame(width: 66, alignment: .trailing)
            Circle().fill(Theme.Colors.brand).frame(width: 7, height: 7).padding(.top, 5)
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
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
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
            reservationID: activity?.reservationID)
        await store.upsertActivity(updated, onDate: date, fromDayID: fromDayID)
        dismiss()
    }
}
