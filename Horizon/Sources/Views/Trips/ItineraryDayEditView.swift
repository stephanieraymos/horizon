import SwiftUI

struct ItineraryDayEditView: View {
    @Environment(TripDetailStore.self) private var detail
    @Environment(\.dismiss) private var dismiss

    @State private var draft: ItineraryDay

    init(day: ItineraryDay) { _draft = State(initialValue: day) }

    var body: some View {
        NavigationStack {
            Form {
                Section("Day") {
                    DatePicker("Date", selection: $draft.dayDate, displayedComponents: .date)
                }

                Section("Activities") {
                    ForEach($draft.activities) { $activity in
                        VStack(alignment: .leading, spacing: 6) {
                            TextField("Activity", text: $activity.title)
                                .font(.body.weight(.medium))
                            TextField("Time (e.g. 9:00 AM)", text: Binding(
                                get: { activity.time ?? "" }, set: { activity.time = $0.nilIfBlank }))
                                .font(.callout)
                            TextField("Location", text: Binding(
                                get: { activity.locationName ?? "" }, set: { activity.locationName = $0.nilIfBlank }))
                                .font(.callout).foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 2)
                    }
                    .onDelete { draft.activities.remove(atOffsets: $0) }

                    Button("Add activity", systemImage: "plus") {
                        draft.activities.append(ItineraryActivity(title: ""))
                    }
                }
            }
            .navigationTitle("Itinerary Day")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
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
