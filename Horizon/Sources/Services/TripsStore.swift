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
    }

    func savePlace(_ place: Place) async {
        do {
            try await supabase.from("fam_places").upsert(place).execute()
            if let i = places.firstIndex(where: { $0.id == place.id }) { places[i] = place }
            else { places.append(place) }
            places.sort { $0.name < $1.name }
        } catch { errorMessage = error.localizedDescription }
    }

    /// Trips that reference a place (by name match on destination, or a linked
    /// reservation/expense place — name match is the reliable cross-cut here).
    func trips(referencingPlace name: String) -> [Trip] {
        let n = name.lowercased()
        return trips.filter { ($0.destination?.lowercased().contains(n) ?? false) }
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

    /// Renames a category and/or changes its icon. A rename repoints every
    /// packing item that used the old name (RLS scopes the update to the family)
    /// so items stay grouped under the new name.
    func updatePackingCategory(_ category: PackingCategoryItem, name: String, icon: String) async {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        struct P: Encodable { let name: String; let icon: String }
        do {
            try await supabase.from("fam_packing_categories")
                .update(P(name: trimmed, icon: icon)).eq("id", value: category.id).execute()
            if trimmed != category.name {
                try await supabase.from("fam_trip_packing")
                    .update(["category": trimmed]).eq("category", value: category.name).execute()
                try await supabase.from("fam_packing_template_items")
                    .update(["category": trimmed]).eq("category", value: category.name).execute()
            }
            if let i = packingCategories.firstIndex(where: { $0.id == category.id }) {
                packingCategories[i].name = trimmed; packingCategories[i].icon = icon
            }
        } catch { errorMessage = error.localizedDescription }
    }

    func deletePackingCategory(_ category: PackingCategoryItem) async {
        do {
            try await supabase.from("fam_packing_categories").delete().eq("id", value: category.id).execute()
            packingCategories.removeAll { $0.id == category.id }
        } catch { errorMessage = error.localizedDescription }
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

    /// Persists a picked location (name + address + maps URL) into the shared
    /// `fam_places` library, unless a same-named place already exists. Used when
    /// a date-night stop is chosen via LocationSearchSheet so it's reusable
    /// across dates and trips. Returns the existing or newly-created place.
    @discardableResult
    func saveIfNew(familyID: UUID, name: String, address: String?, mapsURL: String?,
                   category: String? = nil, latitude: Double? = nil, longitude: Double? = nil) async -> Place? {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        if let existing = places.first(where: { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }) {
            // Backfill address / coordinates / category on an existing bare place.
            if existing.address?.nilIfBlank == nil || existing.latitude == nil {
                var updated = existing
                updated.address = address?.nilIfBlank ?? existing.address
                updated.mapsURL = mapsURL?.nilIfBlank ?? existing.mapsURL
                updated.category = category?.nilIfBlank ?? existing.category
                updated.latitude = latitude ?? existing.latitude
                updated.longitude = longitude ?? existing.longitude
                await savePlace(updated)
                return updated
            }
            return existing
        }
        let place = Place(familyID: familyID, name: trimmed, category: category?.nilIfBlank,
                          address: address?.nilIfBlank, mapsURL: mapsURL?.nilIfBlank,
                          latitude: latitude, longitude: longitude)
        do {
            let row: Place = try await supabase.from("fam_places")
                .insert(place).select().single().execute().value
            places.append(row); places.sort { $0.name < $1.name }
            return row
        } catch { return nil }
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


    // MARK: Derived collections

    var upcoming: [Trip] {
        trips.filter { $0.isUpcoming && !$0.archived }
            .sorted { ($0.departDate ?? .distantFuture) < ($1.departDate ?? .distantFuture) }
    }

    var past: [Trip] {
        trips.filter { $0.isPast && !$0.archived }
            .sorted { ($0.departDate ?? .distantPast) > ($1.departDate ?? .distantPast) }
    }

    var somedayTrips: [Trip] {
        trips.filter { $0.isSomeday && !$0.archived }.sorted { $0.name < $1.name }
    }

    var archivedTrips: [Trip] {
        trips.filter(\.archived)
            .sorted { ($0.departDate ?? .distantPast) > ($1.departDate ?? .distantPast) }
    }

    /// Marks a trip "not going" (or restores it). Persists just the flag.
    func setArchived(_ trip: Trip, _ archived: Bool) async {
        struct P: Encodable { let archived: Bool }
        do {
            try await supabase.from("fam_trips").update(P(archived: archived)).eq("id", value: trip.id).execute()
            if let i = trips.firstIndex(where: { $0.id == trip.id }) { trips[i].archived = archived }
        } catch { errorMessage = error.localizedDescription }
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
    /// keep showing the previous cover. Returns false on failure.
    @discardableResult
    func setTripCover(tripID: UUID, familyID: UUID, imageData: Data) async -> Bool {
        // Lowercase: storage RLS matches the family-id segment against a lowercase uuid.
        let path = "\(familyID.uuidString.lowercased())/covers/trip-\(tripID.uuidString.lowercased())-\(UUID().uuidString.lowercased()).jpg"
        struct P: Encodable { let cover_photo_url: String }
        do {
            try await StorageService.upload(path: path, data: imageData, contentType: "image/jpeg")
            try await supabase.from("fam_trips").update(P(cover_photo_url: path)).eq("id", value: tripID).execute()
            if let i = trips.firstIndex(where: { $0.id == tripID }) { trips[i].coverPhotoURL = path }
            return true
        } catch { errorMessage = error.localizedDescription; return false }
    }

    /// Persists the framing focal point for a trip's cover photo.
    func saveCoverFocus(tripID: UUID, x: Double, y: Double) async {
        struct P: Encodable { let cover_focus_x: Double; let cover_focus_y: Double }
        do {
            try await supabase.from("fam_trips").update(P(cover_focus_x: x, cover_focus_y: y)).eq("id", value: tripID).execute()
            if let i = trips.firstIndex(where: { $0.id == tripID }) { trips[i].coverFocusX = x; trips[i].coverFocusY = y }
        } catch { errorMessage = error.localizedDescription }
    }

    /// Writes the cached forecast onto the trip row.
    func saveWeatherCache(tripID: UUID, cache: WeatherCache) async {
        struct P: Encodable { let weather_cache: WeatherCache }
        do {
            try await supabase.from("fam_trips").update(P(weather_cache: cache)).eq("id", value: tripID).execute()
            if let i = trips.firstIndex(where: { $0.id == tripID }) { trips[i].weatherCache = cache }
        } catch { /* non-fatal — caching is best-effort */ }
    }

    /// Clears a trip's cover photo (the storage object is left; the row just
    /// stops pointing at it).
    func clearTripCover(tripID: UUID) async {
        struct P: Encodable { let cover_photo_url: String? }
        do {
            try await supabase.from("fam_trips").update(P(cover_photo_url: nil)).eq("id", value: tripID).execute()
            if let i = trips.firstIndex(where: { $0.id == tripID }) { trips[i].coverPhotoURL = nil }
        } catch { errorMessage = error.localizedDescription }
    }

    func setDestinationCover(id: UUID, familyID: UUID, imageData: Data) async {
        let path = "\(familyID.uuidString.lowercased())/covers/dest-\(id.uuidString.lowercased())-\(UUID().uuidString.lowercased()).jpg"
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

    /// Links a destination to a place (its real location), so any trip using
    /// this destination knows where it is (weather, maps).
    func setDestinationPlace(id: UUID, placeID: UUID?) async {
        struct P: Encodable { let place_id: UUID? }
        do {
            try await supabase.from("fam_destinations").update(P(place_id: placeID)).eq("id", value: id).execute()
            if let i = destinations.firstIndex(where: { $0.id == id }) { destinations[i].placeID = placeID }
        } catch { errorMessage = error.localizedDescription }
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
