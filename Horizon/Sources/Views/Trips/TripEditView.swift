import SwiftUI

/// Create or edit a trip. Toggling off "Set dates" makes it a Someday/TBD trip
/// (no dates), which lands it in the Someday tab and shows a "Someday" badge.
struct TripEditView: View {
    @Environment(TripsStore.self) private var trips
    @Environment(FamilyStore.self) private var family
    @Environment(EventsStore.self) private var events
    @Environment(\.dismiss) private var dismiss

    @State private var draft: Trip
    @State private var hasDates: Bool
    @State private var multiDay: Bool
    @State private var departDate: Date
    @State private var returnDate: Date
    @State private var overnight: Bool
    /// Set once she flips "Staying overnight" (or the plan already had its own
    /// value). Until then the switch follows the plan's type.
    @State private var overnightChosen: Bool
    @State private var budgetText: String
    @State private var destText: String
    @State private var travelers: [String]
    /// Start time on the first day. Saved on its own (TripsStore.saveStartTime),
    /// never through the full-row upsert, so no other trip save can clear it.
    @State private var hasStartTime: Bool
    @State private var startTime: Date
    private let isNew: Bool

    init(trip: Trip) {
        _draft = State(initialValue: trip)
        let depart = trip.departDate
        _hasDates = State(initialValue: depart != nil)
        _multiDay = State(initialValue: trip.returnDate != nil)
        _departDate = State(initialValue: depart ?? Date())
        _returnDate = State(initialValue: trip.returnDate ?? depart ?? Date())
        _overnight = State(initialValue: trip.staysOvernight)
        _overnightChosen = State(initialValue: trip.overnight != nil)
        _budgetText = State(initialValue: trip.budget.map { String(Int($0)) } ?? "")
        _destText = State(initialValue: trip.destination ?? "")
        _travelers = State(initialValue: trip.travelers ?? [])
        _hasStartTime = State(initialValue: TimeOfDay.components(trip.startTime) != nil)
        _startTime = State(initialValue: TimeOfDay.pickerDate(trip.startTime))
        isNew = trip.createdAt == nil && trip.name.isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("\(draft.kind.label) name", text: $draft.name)
                    Picker("Type", selection: $draft.kind) {
                        ForEach(PlanKind.allCases, id: \.self) { k in
                            Label(k.label, systemImage: k.systemImage).tag(k)
                        }
                    }
                }

                Section {
                    // The id is reconciled authoritatively in save() from the final
                    // text (find-or-create), so retyping/clearing can't leave a
                    // stale grouping and there's no create/save race.
                    ComboField(
                        placeholder: "Search or add a \(draft.kind.locationLabel.lowercased())",
                        text: $destText,
                        options: destinationOptions,
                        pickIcon: "mappin.and.ellipse",
                        mapSearch: true)
                } header: {
                    Text(draft.kind.locationLabel)
                } footer: {
                    if draft.kind.isTravel {
                        Text("Trips sharing a destination (Disneyland, AfterShock…) group together.")
                    }
                }

                Section {
                    Toggle(draft.kind.isTravel ? "Set dates" : "Set a date", isOn: $hasDates.animation())
                    if hasDates {
                        DatePicker(!multiDay ? "Date" : (overnight ? "Depart" : "First day"),
                                   selection: $departDate, displayedComponents: .date)
                        Toggle("Start time", isOn: $hasStartTime.animation())
                        if hasStartTime {
                            DatePicker("Starts at", selection: $startTime, displayedComponents: .hourAndMinute)
                        }
                        Toggle("Multi-day", isOn: $multiDay.animation())
                        if multiDay {
                            DatePicker(overnight ? "Return" : "Last day", selection: $returnDate,
                                       in: departDate..., displayedComponents: .date)
                            Toggle("Staying overnight", isOn: Binding(
                                get: { overnight },
                                set: { newValue in
                                    withAnimation { overnight = newValue }
                                    overnightChosen = true
                                }))
                        }
                    } else {
                        Label("Someday — no dates yet", systemImage: "sparkles")
                            .foregroundStyle(.secondary).font(.callout)
                    }
                } header: {
                    Text("Dates")
                } footer: {
                    if hasDates && multiDay && draftNights > 0 {
                        Text(overnight
                             ? "Counted in nights — \(draftNights) night\(draftNights == 1 ? "" : "s")."
                             : "Counted in days — \(draftNights + 1) days. For something you go to each day and come home from, like a festival.")
                    }
                }

                Section("Status") {
                    Picker("Status", selection: $draft.status) {
                        ForEach(TripStatus.allCases, id: \.self) { s in
                            Label(s.label(for: draft.kind), systemImage: s.systemImage(for: draft.kind)).tag(s)
                        }
                    }
                }

                Section(draft.kind.peopleLabel) {
                    TravelerField(
                        selected: $travelers,
                        members: family.members,
                        onCreate: { await family.createMember(name: $0)?.name },
                        placeholder: draft.kind.isTravel ? "Add a traveler" : "Add a guest")
                }

                Section("Details") {
                    if draft.kind.isTravel {
                        TextField("Transportation", text: Binding(
                            get: { draft.transportation ?? "" },
                            set: { draft.transportation = $0.nilIfBlank }
                        ))
                    }
                    TextField("Budget (USD)", text: $budgetText)
                        #if !targetEnvironment(macCatalyst)
                        .keyboardType(.numberPad)
                        #endif
                }
            }
            .navigationTitle(isNew ? "New \(draft.kind.label)" : "Edit \(draft.kind.label)")
            // The switch follows the plan's type (a trip stays over, a party
            // doesn't) until she sets it herself.
            .onChange(of: draft.kind) { _, kind in if !overnightChosen { overnight = kind.isTravel } }
            // Multi-day starts with a real span, and moving the first day past the
            // last drags the last day along — the picker's `in:` range doesn't move
            // a date that's already set, which let a plan save ending before it began.
            .onChange(of: multiDay) { _, on in
                if on && returnDate <= departDate {
                    returnDate = Calendar.current.date(byAdding: .day, value: 1, to: departDate) ?? departDate
                }
            }
            .onChange(of: departDate) { _, start in
                if returnDate < start { returnDate = start }
            }
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

    private var draftNights: Int {
        max(0, Calendar.current.dateComponents([.day], from: departDate, to: returnDate).day ?? 0)
    }

    private func save() async {
        draft.departDate = hasDates ? departDate : nil
        draft.returnDate = (hasDates && multiDay) ? returnDate : nil
        // Store only a choice that differs from the type's default, so a plan whose
        // type changes later still gets the new type's default.
        draft.overnight = (hasDates && multiDay && overnight != draft.kind.isTravel) ? overnight : nil
        // Reconcile the destination grouping from the final text: match an
        // existing destination (case-insensitive), else create it, else clear.
        if let name = destText.nilIfBlank {
            draft.destination = name
            if let match = trips.destinations.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
                draft.destinationID = match.id
            } else {
                draft.destinationID = await trips.createDestination(familyID: draft.familyID, name: name)?.id
            }
        } else {
            draft.destination = nil
            draft.destinationID = nil
        }
        draft.travelers = travelers.isEmpty ? nil : travelers
        draft.budget = Double(budgetText.filter(\.isNumber))
        if draft.createdBy == nil { draft.createdBy = family.currentMember?.id }
        await trips.save(draft)
        // Only when it changed: a single-column patch (explicit null to clear).
        // No dates means no start time either.
        let newStart = (hasDates && hasStartTime) ? TimeOfDay.string(from: startTime) : nil
        let oldStart = TimeOfDay.components(draft.startTime)
            .map { String(format: "%02d:%02d:00", $0.hour ?? 0, $0.minute ?? 0) }
        if newStart != oldStart {
            await trips.saveStartTime(tripID: draft.id, time: newStart)
        }
        // A dated trip automatically gets (and keeps in sync) a linked countdown.
        await events.syncCountdown(forTripID: draft.id, familyID: draft.familyID,
                                   name: draft.name, departDate: draft.departDate,
                                   createdBy: family.currentMember?.userID)
        dismiss()
    }
}
