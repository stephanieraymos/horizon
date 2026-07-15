import SwiftUI

/// Shared "make something from a countdown" flow used by both the Countdown board
/// and Home. Tapping a date offers: a one-day event (a countdown), a multi-day
/// event (a trip), and — for real events — linking/editing.
///
/// A countdown is always a single date, so the choice is about what you're
/// creating *around* it: a one-day thing vs a multi-day trip.
struct EventActions: ViewModifier {
    @Binding var event: FamilyEvent?
    var allowLinkEdit: Bool = true
    var onOpenTrip: (Trip) -> Void
    var onLinkTrip: (FamilyEvent) -> Void = { _ in }
    var onEditCountdown: (FamilyEvent) -> Void = { _ in }

    @Environment(EventsStore.self) private var events
    @Environment(FamilyStore.self) private var family
    @Environment(TripsStore.self) private var trips

    @State private var creatingOneDayFrom: FamilyEvent?

    private var memberIDs: Set<UUID> { Set(family.members.map(\.id)) }
    /// A synthetic member-birthday has no real fam_events row to link/edit.
    private func isSynthetic(_ e: FamilyEvent) -> Bool {
        e.eventType == FamilyEventType.birthday.rawValue && memberIDs.contains(e.id)
    }
    /// Annual events (birthdays) seed the next upcoming occurrence, not the
    /// possibly-long-past original date.
    private func seedDate(_ e: FamilyEvent) -> Date {
        e.isAnnual ? e.nextOccurrenceDate : e.eventDate
    }

    func body(content: Content) -> some View {
        content
            .confirmationDialog("Make from this date",
                                isPresented: Binding(get: { event != nil },
                                                     set: { if !$0 { event = nil } }),
                                presenting: event) { ev in
                Button("Create one-day event") {
                    let e = ev; event = nil; creatingOneDayFrom = e
                }
                Button("Create multi-day event") {
                    let e = ev; event = nil; Task { await createTrip(from: e) }
                }
                if allowLinkEdit && !isSynthetic(ev) {
                    Button("Link an existing trip") {
                        let e = ev; event = nil
                        Task { @MainActor in
                            try? await Task.sleep(nanoseconds: 300_000_000)
                            onLinkTrip(e)
                        }
                    }
                    Button("Edit countdown") { let e = ev; event = nil; onEditCountdown(e) }
                }
                Button("Cancel", role: .cancel) {}
            } message: { ev in
                Text("Add “\(ev.title)” as a one-day event, or plan a multi-day trip around it.")
            }
            .sheet(item: $creatingOneDayFrom) { ev in
                EventEditView(existing: nil, prefillTitle: ev.title, prefillDate: seedDate(ev))
            }
    }

    private func createTrip(from event: FamilyEvent) async {
        guard let familyID = family.familyID else { return }
        let date = seedDate(event)
        let trip = Trip(familyID: familyID, name: event.title, departDate: date,
                        status: .planning, createdBy: family.currentMember?.id)
        await trips.save(trip)
        if isSynthetic(event) {
            // Synthetic birthdays have no fam_events row to link; give the new
            // trip its own countdown instead.
            await events.syncCountdown(forTripID: trip.id, familyID: familyID,
                                       name: trip.name, departDate: date,
                                       createdBy: family.currentMember?.userID)
        } else {
            await events.linkTrip(event, tripID: trip.id)
        }
        try? await Task.sleep(nanoseconds: 300_000_000)
        onOpenTrip(trips.trips.first { $0.id == trip.id } ?? trip)
    }
}

extension View {
    func eventActions(event: Binding<FamilyEvent?>,
                      allowLinkEdit: Bool = true,
                      onOpenTrip: @escaping (Trip) -> Void,
                      onLinkTrip: @escaping (FamilyEvent) -> Void = { _ in },
                      onEditCountdown: @escaping (FamilyEvent) -> Void = { _ in }) -> some View {
        modifier(EventActions(event: event, allowLinkEdit: allowLinkEdit,
                              onOpenTrip: onOpenTrip, onLinkTrip: onLinkTrip,
                              onEditCountdown: onEditCountdown))
    }
}
