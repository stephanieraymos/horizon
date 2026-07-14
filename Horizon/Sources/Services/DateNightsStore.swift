import Foundation
import Observation
import Supabase

/// Loads and persists date-night plans from the shared `fam_dates` table. RLS
/// scopes every query to the caller's family. Ideas → scheduled outings → rated
/// memories. (TheGlade's local reminders + calendar-invite side effects are not
/// ported; Horizon just owns the data.)
@Observable
@MainActor
final class DateNightsStore {
    private(set) var dates: [DateNight] = []
    var error: String?

    /// Ideas = idea_only true, no scheduled_at.
    var ideas: [DateNight] {
        dates.filter { $0.ideaOnly }.sorted { $0.title < $1.title }
    }
    /// Upcoming = scheduled_at >= now.
    var upcoming: [DateNight] {
        let now = Date()
        return dates
            .filter { !$0.ideaOnly && ($0.scheduledAt ?? .distantPast) >= now }
            .sorted { ($0.scheduledAt ?? .distantPast) < ($1.scheduledAt ?? .distantPast) }
    }
    /// Past = scheduled_at < now.
    var past: [DateNight] {
        let now = Date()
        return dates
            .filter { !$0.ideaOnly && ($0.scheduledAt ?? .distantFuture) < now }
            .sorted { ($0.scheduledAt ?? .distantPast) > ($1.scheduledAt ?? .distantPast) }
    }

    func load() async {
        do {
            dates = try await supabase
                .from("fam_dates")
                .select()
                .order("scheduled_at", ascending: false)
                .execute()
                .value
        } catch {
            self.error = error.localizedDescription
        }
    }

    @discardableResult
    func save(_ date: DateNight) async -> Bool {
        struct DateUpsert: Encodable {
            let id: UUID
            let family_id: UUID
            let title: String
            let category: String?
            let destinations: [DateNightDestination]?
            let est_cost: Double?
            let notes: String?
            let idea_only: Bool
            let scheduled_at: Date?
            let rating: Int?
            let review_notes: String?
            let photo_url: String?
            let movie_id: UUID?
            let created_by: UUID?
        }
        let payload = DateUpsert(
            id: date.id,
            family_id: date.familyID,
            title: date.title,
            category: date.category,
            destinations: date.destinations?.isEmpty == false ? date.destinations : nil,
            est_cost: date.estCost,
            notes: date.notes,
            idea_only: date.ideaOnly,
            scheduled_at: date.scheduledAt,
            rating: date.rating,
            review_notes: date.reviewNotes,
            photo_url: date.photoURL,
            movie_id: date.movieID,
            created_by: date.createdBy
        )
        do {
            let saved: DateNight = try await supabase
                .from("fam_dates")
                .upsert(payload, onConflict: "id")
                .select()
                .single()
                .execute()
                .value
            if let idx = dates.firstIndex(where: { $0.id == saved.id }) {
                dates[idx] = saved
            } else {
                dates.append(saved)
            }
            return true
        } catch {
            self.error = error.localizedDescription
            return false
        }
    }

    func delete(_ date: DateNight) async {
        do {
            try await supabase.from("fam_dates").delete().eq("id", value: date.id).execute()
            dates.removeAll { $0.id == date.id }
        } catch {
            self.error = error.localizedDescription
        }
    }
}
