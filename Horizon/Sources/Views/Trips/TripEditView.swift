import SwiftUI

/// Create or edit a trip. Toggling off "Set dates" makes it a Someday/TBD trip
/// (no dates), which lands it in the Someday tab and shows a "Someday" badge.
struct TripEditView: View {
    @Environment(TripsStore.self) private var trips
    @Environment(FamilyStore.self) private var family
    @Environment(\.dismiss) private var dismiss

    @State private var draft: Trip
    @State private var hasDates: Bool
    @State private var departDate: Date
    @State private var returnDate: Date
    @State private var budgetText: String
    @State private var travelers: Set<String>
    private let isNew: Bool

    init(trip: Trip) {
        _draft = State(initialValue: trip)
        let depart = trip.departDate
        _hasDates = State(initialValue: depart != nil)
        _departDate = State(initialValue: depart ?? Date())
        _returnDate = State(initialValue: trip.returnDate ?? depart ?? Date())
        _budgetText = State(initialValue: trip.budget.map { String(Int($0)) } ?? "")
        _travelers = State(initialValue: Set(trip.travelers ?? []))
        isNew = trip.createdAt == nil && trip.name.isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Trip name", text: $draft.name)
                    TextField("Destination", text: Binding(
                        get: { draft.destination ?? "" },
                        set: { draft.destination = $0.nilIfBlank }
                    ))
                }

                Section("Dates") {
                    Toggle("Set dates", isOn: $hasDates.animation())
                    if hasDates {
                        DatePicker("Depart", selection: $departDate, displayedComponents: .date)
                        DatePicker("Return", selection: $returnDate, in: departDate..., displayedComponents: .date)
                    } else {
                        Label("Someday — no dates yet", systemImage: "sparkles")
                            .foregroundStyle(.secondary).font(.callout)
                    }
                }

                Section("Status") {
                    Picker("Status", selection: $draft.status) {
                        ForEach(TripStatus.allCases, id: \.self) { s in
                            Label(s.label, systemImage: s.systemImage).tag(s)
                        }
                    }
                }

                if !destinationOptions.isEmpty {
                    Section("Group under destination") {
                        Picker("Destination", selection: Binding(
                            get: { draft.destinationID },
                            set: { draft.destinationID = $0 }
                        )) {
                            Text("None").tag(UUID?.none)
                            ForEach(destinationOptions) { dest in
                                Text(dest.name).tag(UUID?.some(dest.id))
                            }
                        }
                    }
                }

                if !family.members.isEmpty {
                    Section("Travelers") {
                        ForEach(family.members) { member in
                            Button {
                                toggle(member.name)
                            } label: {
                                HStack {
                                    Text(member.name).foregroundStyle(.primary)
                                    Spacer()
                                    if travelers.contains(member.name) {
                                        Image(systemName: "checkmark").foregroundStyle(Theme.Colors.brand)
                                    }
                                }
                            }
                        }
                    }
                }

                Section("Details") {
                    TextField("Transportation", text: Binding(
                        get: { draft.transportation ?? "" },
                        set: { draft.transportation = $0.nilIfBlank }
                    ))
                    TextField("Budget (USD)", text: $budgetText)
                        #if !targetEnvironment(macCatalyst)
                        .keyboardType(.numberPad)
                        #endif
                }
            }
            .navigationTitle(isNew ? "New Trip" : "Edit Trip")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await save() } }
                        .disabled(draft.name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private var destinationOptions: [Destination] {
        trips.destinations.sorted { $0.name < $1.name }
    }

    private func toggle(_ name: String) {
        if travelers.contains(name) { travelers.remove(name) } else { travelers.insert(name) }
    }

    private func save() async {
        draft.departDate = hasDates ? departDate : nil
        draft.returnDate = hasDates ? returnDate : nil
        draft.travelers = travelers.isEmpty ? nil : Array(travelers).sorted()
        draft.budget = Double(budgetText.filter(\.isNumber))
        if draft.createdBy == nil { draft.createdBy = family.currentMember?.id }
        await trips.save(draft)
        dismiss()
    }
}
