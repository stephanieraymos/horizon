import Foundation
import Observation
import Supabase
import WidgetKit

/// Loads and persists trips + destinations from the shared `fam_trips` /
/// `fam_destinations` tables. RLS scopes every query to the caller's family.
@Observable
@MainActor
final class TripsStore {
    var trips: [Trip] = []
    var destinations: [Destination] = []
    var places: [Place] = []
    var packingCategories: [PackingCategoryItem] = []
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
        do {
            places = try await supabase.from("fam_places").select().order("name").execute().value
        } catch { /* non-fatal */ }
        do {
            packingCategories = try await supabase.from("fam_packing_categories")
                .select().order("sort").execute().value
        } catch { /* non-fatal */ }
        publishWidgetSnapshot()
    }

    func icon(forCategory name: String?) -> String {
        guard let name else { return "shippingbox" }
        return packingCategories.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }?.icon ?? "shippingbox"
    }

    @discardableResult
    func createPackingCategory(familyID: UUID, name: String, icon: String) async -> PackingCategoryItem? {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        if let existing = packingCategories.first(where: { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }) {
            return existing
        }
        do {
            let row: PackingCategoryItem = try await supabase.from("fam_packing_categories")
                .insert(PackingCategoryItem(familyID: familyID, name: trimmed, icon: icon,
                                            sort: packingCategories.count))
                .select().single().execute().value
            packingCategories.append(row)
            return row
        } catch { return nil }
    }

    func updatePackingCategoryIcon(_ category: PackingCategoryItem, icon: String) async {
        do {
            try await supabase.from("fam_packing_categories")
                .update(["icon": icon]).eq("id", value: category.id).execute()
            if let i = packingCategories.firstIndex(where: { $0.id == category.id }) {
                packingCategories[i].icon = icon
            }
        } catch { errorMessage = error.localizedDescription }
    }

    /// Inserts a place and returns it (for inline "add new" in location pickers).
    @discardableResult
    func createPlace(familyID: UUID, name: String) async -> Place? {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        if let existing = places.first(where: { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }) {
            return existing
        }
        do {
            let row: Place = try await supabase.from("fam_places")
                .insert(Place(familyID: familyID, name: trimmed)).select().single().execute().value
            places.append(row); places.sort { $0.name < $1.name }
            return row
        } catch { return nil }
    }

    /// Writes the next-trip snapshot to the App Group and refreshes widgets.
    /// Foundation-only payload — the widget can't hold a Supabase session.
    private func publishWidgetSnapshot() {
        let next = upcoming.first
        let snap = TripWidgetSnapshot(
            generatedAt: Date(),
            tripName: next?.name,
            destination: next.flatMap { destination(for: $0)?.name ?? $0.destination },
            departDate: next?.departDate,
            returnDate: next?.returnDate,
            isSomeday: next?.isSomeday ?? false,
            upcomingCount: upcoming.count)
        TripWidgetSnapshot.save(snap)
        WidgetCenter.shared.reloadAllTimelines()
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

    /// Uploads a cover photo and links it to the trip (stores the storage path).
    /// A fresh filename per upload changes cover_photo_url so cached images don't
    /// keep showing the previous cover.
    func setTripCover(tripID: UUID, familyID: UUID, imageData: Data) async {
        let path = "\(familyID.uuidString)/covers/trip-\(tripID.uuidString)-\(UUID().uuidString).jpg"
        struct P: Encodable { let cover_photo_url: String }
        do {
            try await StorageService.upload(path: path, data: imageData, contentType: "image/jpeg")
            try await supabase.from("fam_trips").update(P(cover_photo_url: path)).eq("id", value: tripID).execute()
            if let i = trips.firstIndex(where: { $0.id == tripID }) { trips[i].coverPhotoURL = path }
        } catch { errorMessage = error.localizedDescription }
    }

    func setDestinationCover(id: UUID, familyID: UUID, imageData: Data) async {
        let path = "\(familyID.uuidString)/covers/dest-\(id.uuidString)-\(UUID().uuidString).jpg"
        struct P: Encodable { let cover_photo_url: String }
        do {
            try await StorageService.upload(path: path, data: imageData, contentType: "image/jpeg")
            try await supabase.from("fam_destinations").update(P(cover_photo_url: path)).eq("id", value: id).execute()
            if let i = destinations.firstIndex(where: { $0.id == id }) { destinations[i].coverPhotoURL = path }
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

    /// Inserts a destination and returns it (for inline "add new" in pickers).
    /// Reuses an existing same-named destination if present.
    @discardableResult
    func createDestination(familyID: UUID, name: String) async -> Destination? {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        if let existing = destinations.first(where: { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }) {
            return existing
        }
        do {
            let row: Destination = try await supabase
                .from("fam_destinations")
                .insert(Destination(familyID: familyID, name: trimmed))
                .select().single().execute().value
            destinations.append(row)
            destinations.sort { $0.name < $1.name }
            return row
        } catch {
            errorMessage = error.localizedDescription
            return nil
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

    func renameDestination(_ destination: Destination, name: String) async {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        struct P: Encodable { let name: String }
        do {
            try await supabase.from("fam_destinations").update(P(name: trimmed)).eq("id", value: destination.id).execute()
            if let i = destinations.firstIndex(where: { $0.id == destination.id }) { destinations[i].name = trimmed }
        } catch { errorMessage = error.localizedDescription }
    }

    func trips(forDestination id: UUID) -> [Trip] {
        trips.filter { $0.destinationID == id }
            .sorted { ($0.departDate ?? .distantPast) > ($1.departDate ?? .distantPast) }
    }

    func tripCount(forDestination id: UUID) -> Int {
        trips.reduce(0) { $0 + ($1.destinationID == id ? 1 : 0) }
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
