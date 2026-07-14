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
}
