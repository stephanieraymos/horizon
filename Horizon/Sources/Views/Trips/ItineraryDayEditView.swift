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
