import Foundation
import Observation
import Supabase

/// Loads and persists trips + destinations from the shared `fam_trips` /
/// `fam_destinations` tables. RLS scopes every query to the caller's family.
@Observable
@MainActor
final class TripsStore {
    var trips: [Trip] = []
    var destinations: [Destination] = []
    var isLoading = false
    var errorMessage: String?

    // MARK: Load

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            trips = try await supabase
                .from("fam_trips")
                .select()
                .order("depart_date", ascending: true, nullsFirst: false)
                .execute()
                .value
        } catch {
            errorMessage = error.localizedDescription
        }
        do {
            destinations = try await supabase
                .from("fam_destinations")
                .select()
                .order("name")
                .execute()
                .value
        } catch {
            // Non-fatal — destinations are supplementary.
        }
    }

    // MARK: Derived collections

    var upcoming: [Trip] {
        trips.filter(\.isUpcoming)
            .sorted { ($0.departDate ?? .distantFuture) < ($1.departDate ?? .distantFuture) }
    }

    var past: [Trip] {
        trips.filter(\.isPast)
            .sorted { ($0.departDate ?? .distantPast) > ($1.departDate ?? .distantPast) }
    }

    var somedayTrips: [Trip] {
        trips.filter(\.isSomeday).sorted { $0.name < $1.name }
    }

    var wishlistDestinations: [Destination] {
        destinations.filter(\.isWishlist).sorted { $0.name < $1.name }
    }

    func destination(for trip: Trip) -> Destination? {
        guard let id = trip.destinationID else { return nil }
        return destinations.first { $0.id == id }
    }

    // MARK: Mutations

    func save(_ trip: Trip) async {
        do {
            try await supabase.from("fam_trips").upsert(trip).execute()
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Saves just the rich-text notes column, so a full trip upsert can't clobber it.
    func saveTripNotes(tripID: UUID, blocks: [ContentBlock]) async {
        struct Payload: Encodable { let notes_content: [ContentBlock] }
        do {
            try await supabase.from("fam_trips")
                .update(Payload(notes_content: blocks)).eq("id", value: tripID).execute()
            if let i = trips.firstIndex(where: { $0.id == tripID }) { trips[i].notesContent = blocks }
        } catch { errorMessage = error.localizedDescription }
    }

    func delete(_ trip: Trip) async {
        do {
            try await supabase.from("fam_trips").delete().eq("id", value: trip.id).execute()
            trips.removeAll { $0.id == trip.id }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func saveDestination(_ destination: Destination) async {
        do {
            try await supabase.from("fam_destinations").upsert(destination).execute()
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func deleteDestination(_ destination: Destination) async {
        do {
            try await supabase.from("fam_destinations").delete().eq("id", value: destination.id).execute()
            destinations.removeAll { $0.id == destination.id }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
