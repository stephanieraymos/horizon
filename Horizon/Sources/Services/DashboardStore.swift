import Foundation
import Observation
import Supabase

/// Cross-trip data for the Home dashboard — currently the next upcoming
/// reservations across all trips ("your flight is tomorrow").
@Observable
@MainActor
final class DashboardStore {
    private(set) var upcomingReservations: [Reservation] = []

    func load() async {
        let iso = ISO8601DateFormatter().string(from: Date())
        do {
            upcomingReservations = try await supabase.from("fam_reservations")
                .select()
                .gte("start_at", value: iso)
                .order("start_at", ascending: true)
                .limit(6)
                .execute()
                .value
        } catch {
            // Non-fatal — the dashboard just omits the reservations row.
        }
    }
}
