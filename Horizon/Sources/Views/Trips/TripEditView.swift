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
    @State private var destText: String
    @State private var travelers: [String]
    private let isNew: Bool

    init(trip: Trip) {
        _draft = State(initialValue: trip)
        let depart = trip.departDate
        _hasDates = State(initialValue: depart != nil)
        _departDate = State(initialValue: depart ?? Date())
        _returnDate = State(initialValue: trip.returnDate ?? depart ?? Date())
        _budgetText = State(initialValue: trip.budget.map { String(Int($0)) } ?? "")
        _destText = State(initialValue: trip.destination ?? "")
        _travelers = State(initialValue: trip.travelers ?? [])
        isNew = trip.createdAt == nil && trip.name.isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Trip name", text: $draft.name)
                }

                Section {
                    ComboField(
                        placeholder: "Search or add a destination",
                        text: $destText,
                        options: destinationOptions,
                        pickIcon: "mappin.and.ellipse",
                        onPick: { opt in draft.destinationID = UUID(uuidString: opt.id) },
                        onAdd: { name in
                            Task {
                                if let d = await trips.createDestination(familyID: draft.familyID, name: name) {
                                    draft.destinationID = d.id
                                }
                            }
                        })
                } header: {
                    Text("Destination")
                } footer: {
                    Text("Trips sharing a destination (Disneyland, AfterShock…) group together.")
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

                Section("Travelers") {
                    TravelerField(
                        selected: $travelers,
                        members: family.members,
                        onCreate: { await family.createMember(name: $0)?.name })
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

    private var destinationOptions: [ComboField.Option] {
        trips.destinations.sorted { $0.name < $1.name }.map {
            .init(id: $0.id.uuidString, name: $0.name, icon: "mappin.and.ellipse")
        }
    }

    private func save() async {
        draft.departDate = hasDates ? departDate : nil
        draft.returnDate = hasDates ? returnDate : nil
        draft.destination = destText.nilIfBlank
        draft.travelers = travelers.isEmpty ? nil : travelers
        draft.budget = Double(budgetText.filter(\.isNumber))
        if draft.createdBy == nil { draft.createdBy = family.currentMember?.id }
        await trips.save(draft)
        dismiss()
    }
}
