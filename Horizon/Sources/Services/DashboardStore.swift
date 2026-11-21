import Foundation
import Observation
import Supabase

/// Cross-trip data for the Home dashboard — currently the next upcoming
/// reservations across all trips ("your flight is tomorrow").
@Observable
@MainActor
final class DashboardStore {
    private(set) var upcomingReservations: [Reservation] = []

    /// When the last SUCCESSFUL load finished (stamped after the await, never before).
    private var loadedAt: Date?

    /// Loads unless a load succeeded within `ttl` seconds. The sidebar shell remounts
    /// Home on every sidebar tap, so its `.task` would otherwise refetch each time.
    func loadIfStale(ttl: TimeInterval = 60) async {
        if let loadedAt, Date().timeIntervalSince(loadedAt) < ttl { return }
        await load()
    }

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
            loadedAt = Date()
        } catch {
            // Non-fatal — the dashboard just omits the reservations row.
        }
    }
}
