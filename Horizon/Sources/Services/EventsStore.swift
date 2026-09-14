import Foundation
import Observation
import Supabase

/// Loads and persists dated family milestones from the shared `fam_events`
/// table. RLS scopes every query to the caller's family. Powers the Countdown
/// tab's day-away board.
@Observable
@MainActor
final class EventsStore {
    private(set) var events: [FamilyEvent] = []
    private(set) var isLoading = false
    var error: String?

    /// Upcoming events, sorted by next display date.
    /// Annual events always appear here (they always have a future occurrence).
    var upcoming: [FamilyEvent] {
        let today = Calendar.current.startOfDay(for: Date())
        return events
            .filter {
                let date = $0.isAnnual ? $0.nextOccurrenceDate : $0.eventDate
                return Calendar.current.startOfDay(for: date) >= today
            }
            .sorted {
                let d0 = $0.isAnnual ? $0.nextOccurrenceDate : $0.eventDate
                let d1 = $1.isAnnual ? $1.nextOccurrenceDate : $1.eventDate
                return d0 < d1
            }
    }

    /// Past events — excludes annual events since they always recur.
    var memories: [FamilyEvent] {
        let today = Calendar.current.startOfDay(for: Date())
        return events
            .filter {
                guard !$0.isAnnual else { return false }
                return Calendar.current.startOfDay(for: $0.eventDate) < today
            }
            .sorted { $0.eventDate > $1.eventDate }
    }

    func load() async {
        #if DEBUG
        guard !DemoMode.isActive else { return }
        #endif
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            events = try await supabase
                .from("fam_events")
                .select()
                .order("event_date", ascending: true)
                .execute()
                .value
        } catch {
            self.error = error.localizedDescription
        }
    }

    @discardableResult
    func upsert(
        id: UUID?,
        familyID: UUID,
        title: String,
        eventType: String?,
        eventDate: Date,
        isAnnual: Bool,
        description: String?,
        emoji: String?,
        members: [String]?,
        tripID: UUID? = nil,
        createdBy: UUID?
    ) async -> Bool {
        struct EventUpsert: Encodable {
            let id: UUID?
            let family_id: UUID
            let title: String
            let event_type: String?
            let event_date: String
            let is_annual: Bool
            let description: String?
            let emoji: String?
            let members: [String]?
            let trip_id: UUID?
            let created_by: UUID?
        }

        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone.current

        let payload = EventUpsert(
            id: id,
            family_id: familyID,
            title: title,
            event_type: eventType?.nilIfBlank,
            event_date: f.string(from: eventDate),
            is_annual: isAnnual,
            description: description?.nilIfBlank,
            emoji: emoji?.nilIfBlank,
            members: members?.isEmpty == false ? members : nil,
            trip_id: tripID,
            created_by: createdBy
        )

        do {
            let saved: FamilyEvent = try await supabase
                .from("fam_events")
                .upsert(payload, onConflict: "id")
                .select()
                .single()
                .execute()
                .value
            if let idx = events.firstIndex(where: { $0.id == saved.id }) {
                events[idx] = saved
            } else {
                events.append(saved)
            }
            return true
        } catch {
            self.error = error.localizedDescription
            return false
        }
    }

    func delete(_ event: FamilyEvent) async {
        do {
            try await supabase
                .from("fam_events")
                .delete()
                .eq("id", value: event.id)
                .execute()
            events.removeAll { $0.id == event.id }
        } catch {
            self.error = error.localizedDescription
        }
    }

    #if DEBUG
    /// Demo mode only (`DemoMode`): replace the rows without a fetch.
    func replaceForDemo(_ rows: [FamilyEvent]) { events = rows }
    #endif

    // MARK: - Trip linking

    /// The (loaded) countdown linked to a trip, if any.
    func event(forTrip tripID: UUID) -> FamilyEvent? {
        events.first { $0.tripID == tripID }
    }

    /// Sets or clears the trip link on an existing countdown.
    func linkTrip(_ event: FamilyEvent, tripID: UUID?) async {
        do {
            try await supabase.from("fam_events")
                .update(TripLinkPatch(trip_id: tripID)).eq("id", value: event.id).execute()
            if let i = events.firstIndex(where: { $0.id == event.id }) { events[i].tripID = tripID }
        } catch { self.error = error.localizedDescription }
    }

    /// Ensures a dated trip has a linked countdown, creating it or keeping its
    /// title/date in sync. Someday trips (no depart date) are skipped. Returns
    /// the linked event's id if one exists/was created.
    @discardableResult
    func syncCountdown(forTripID tripID: UUID, familyID: UUID, name: String,
                       departDate: Date?, createdBy: UUID?) async -> UUID? {
        guard let departDate else { return nil }

        // Every row linked to the plan (query in case events aren't loaded).
        var linked = events.filter { $0.tripID == tripID }
        if linked.isEmpty {
            let fetched: [FamilyEvent]? = try? await supabase.from("fam_events")
                .select().eq("trip_id", value: tripID).limit(10).execute().value
            linked = fetched ?? []
        }
        let copy = linked.first(where: \.isPlanCopy)

        // A countdown the plan was made FROM ("Plan a dinner" on the anniversary)
        // is hers and is never touched here — rewriting it turned an annual
        // anniversary into a one-off "Vacation ✈️" named after the dinner. While
        // it sits on the plan's day it already marks that day (Solstice's
        // calendar reads these rows), so no copy is written; once the plan moves
        // off it, the plan gets a copy of its own.
        let cal = Calendar.current
        let marked = linked.first { e in
            !e.isPlanCopy && cal.isDate(e.isAnnual ? e.nextOccurrenceDate : e.eventDate,
                                        inSameDayAs: departDate)
        }
        if let marked {
            // Back on the countdown's day: a copy here would put the day on
            // Solstice's calendar twice, so the copy from when it moved away goes.
            if let copy { await delete(copy) }
            return marked.id
        }

        await upsert(
            id: copy?.id,
            familyID: familyID,
            title: name,
            eventType: FamilyEventType.vacation.rawValue,
            eventDate: departDate,
            isAnnual: false,
            description: copy?.description,
            emoji: copy?.emoji ?? "✈️",
            members: copy?.members,
            tripID: tripID,
            createdBy: copy?.createdBy ?? createdBy)
        return events.first { $0.tripID == tripID && $0.isPlanCopy }?.id ?? copy?.id
    }

    /// Removes the plan's own countdown copy and — unless `keepingLinks` — UNLINKS
    /// any countdown the plan was made from, which is hers and outlives the plan.
    /// This deleted every linked row, so marking the anniversary dinner "Not
    /// going" deleted the anniversary.
    ///
    /// "Not going" keeps the link (`keepingLinks: true`): an archived plan isn't
    /// listed, so the countdown shows on its own anyway, and Restore finds it
    /// still linked instead of writing a second row for the same day.
    func deleteForTrip(_ tripID: UUID, keepingLinks: Bool = false) async {
        do {
            try await supabase.from("fam_events").delete()
                .eq("trip_id", value: tripID)
                .eq("event_type", value: FamilyEventType.vacation.rawValue)
                .eq("is_annual", value: false)
                .execute()
            events.removeAll { $0.tripID == tripID && $0.isPlanCopy }
            guard !keepingLinks else { return }
            try await supabase.from("fam_events")
                .update(TripLinkPatch(trip_id: nil))
                .eq("trip_id", value: tripID)
                .execute()
            for i in events.indices where events[i].tripID == tripID { events[i].tripID = nil }
        } catch { self.error = error.localizedDescription }
    }
}

/// `{"trip_id": …}` — with an explicit null when unlinking. A synthesized
/// Encodable skips a nil optional entirely, so the old `P(trip_id: nil)` sent an
/// empty update and "Unlink" never unlinked anything.
private struct TripLinkPatch: Encodable {
    let trip_id: UUID?
    enum CodingKeys: String, CodingKey { case trip_id }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(trip_id, forKey: .trip_id)
    }
}
