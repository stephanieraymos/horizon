import SwiftUI

struct ItineraryDayEditView: View {
    @Environment(TripDetailStore.self) private var detail
    @Environment(\.dismiss) private var dismiss

    @State private var draft: ItineraryDay

    init(day: ItineraryDay) { _draft = State(initialValue: day) }

    private static let clock: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "h:mm a"
        return f
    }()
    private var defaultTime: Date {
        Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: Date()) ?? Date()
    }
    /// Parses a stored clock string ("9:00 AM"); nil for word slots or all-day.
    private func parsedTime(_ s: String?) -> Date? { s.flatMap { Self.clock.date(from: $0) } }

    var body: some View {
        NavigationStack {
            Form {
                Section("Day") {
                    DatePicker("Date", selection: $draft.dayDate, displayedComponents: .date)
                }

                Section {
                    ForEach($draft.activities) { $activity in
                        VStack(alignment: .leading, spacing: 6) {
                            TextField("Activity", text: $activity.title)
                                .font(.body.weight(.medium))
                            HStack(spacing: 6) {
                                ForEach(["Morning", "Afternoon", "Evening"], id: \.self) { slot in
                                    Button(slot) { activity.time = slot }
                                        .font(.caption)
                                        .buttonStyle(.bordered)
                                        .tint(activity.time == slot ? Theme.Colors.brand : .secondary)
                                }
                            }
                            Toggle("Set a time", isOn: Binding(
                                get: { parsedTime(activity.time) != nil },
                                set: { on in
                                    activity.time = on
                                        ? Self.clock.string(from: parsedTime(activity.time) ?? defaultTime)
                                        : nil
                                }))
                                .font(.callout)
                            if let t = parsedTime(activity.time) {
                                DatePicker("Time", selection: Binding(
                                    get: { t },
                                    set: { activity.time = Self.clock.string(from: $0) }),
                                    displayedComponents: .hourAndMinute)
                                    .font(.callout)
                            }
                            TextField("Location", text: Binding(
                                get: { activity.locationName ?? "" }, set: { activity.locationName = $0.nilIfBlank }))
                                .font(.callout).foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 2)
                    }
                    .onDelete { draft.activities.remove(atOffsets: $0) }
                    .onMove { draft.activities.move(fromOffsets: $0, toOffset: $1) }

                    Button("Add activity", systemImage: "plus") {
                        draft.activities.append(ItineraryActivity(title: ""))
                    }
                } header: {
                    Text("Activities")
                } footer: {
                    Text("Tap Edit to drag activities into order.")
                }
            }
            .navigationTitle("Itinerary Day")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .principal) { EditButton() }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        draft.activities.removeAll { $0.title.trimmingCharacters(in: .whitespaces).isEmpty }
                        Task { await detail.saveDay(draft); dismiss() }
                    }
                }
            }
        }
    }
}
