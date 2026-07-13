import Foundation
import Observation
import Supabase

/// Per-trip sub-data: typed reservations + day-by-day itinerary. One instance
/// per open TripDetailView.
@Observable
@MainActor
final class TripDetailStore {
    let tripID: UUID
    var reservations: [Reservation] = []
    var itinerary: [ItineraryDay] = []
    var isLoading = false
    var errorMessage: String?

    init(tripID: UUID) { self.tripID = tripID }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        async let res = fetchReservations()
        async let days = fetchItinerary()
        reservations = await res
        itinerary = await days
    }

    private func fetchReservations() async -> [Reservation] {
        do {
            return try await supabase.from("fam_reservations")
                .select().eq("trip_id", value: tripID)
                .order("sort").order("start_at", ascending: true, nullsFirst: false)
                .execute().value
        } catch {
            errorMessage = error.localizedDescription
            return []
        }
    }

    private func fetchItinerary() async -> [ItineraryDay] {
        do {
            return try await supabase.from("fam_trip_itinerary")
                .select().eq("trip_id", value: tripID)
                .order("day_date").execute().value
        } catch {
            return []
        }
    }

    // MARK: Reservations

    func saveReservation(_ r: Reservation) async {
        do {
            try await supabase.from("fam_reservations").upsert(r).execute()
            await load()
        } catch { errorMessage = error.localizedDescription }
    }

    func deleteReservation(_ r: Reservation) async {
        do {
            try await supabase.from("fam_reservations").delete().eq("id", value: r.id).execute()
            reservations.removeAll { $0.id == r.id }
        } catch { errorMessage = error.localizedDescription }
    }

    var reservationsByType: [(type: ReservationType, items: [Reservation])] {
        ReservationType.allCases.compactMap { type in
            let items = reservations.filter { $0.type == type }
            return items.isEmpty ? nil : (type, items)
        }
    }

    // MARK: Itinerary

    func saveDay(_ day: ItineraryDay) async {
        do {
            try await supabase.from("fam_trip_itinerary").upsert(day).execute()
            await load()
        } catch { errorMessage = error.localizedDescription }
    }

    func deleteDay(_ day: ItineraryDay) async {
        do {
            try await supabase.from("fam_trip_itinerary").delete().eq("id", value: day.id).execute()
            itinerary.removeAll { $0.id == day.id }
        } catch { errorMessage = error.localizedDescription }
    }
}
