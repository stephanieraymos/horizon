import Foundation

/// Links a `fam_places` place to a trip (many places per trip). Mirror of
/// `fam_trip_places`.
struct TripPlace: Codable, Identifiable, Hashable {
    let id: UUID
    var tripID: UUID
    var placeID: UUID
    var familyID: UUID
    var sort: Int

    enum CodingKeys: String, CodingKey {
        case id
        case tripID = "trip_id"
        case placeID = "place_id"
        case familyID = "family_id"
        case sort
    }

    init(id: UUID = UUID(), tripID: UUID, placeID: UUID, familyID: UUID, sort: Int = 0) {
        self.id = id; self.tripID = tripID; self.placeID = placeID; self.familyID = familyID; self.sort = sort
    }
}

extension Place {
    /// SF Symbol for a place category (Hotel, Restaurant, …).
    var categoryIcon: String {
        switch category?.lowercased() {
        case "hotel", "lodging", "stay": return "bed.double.fill"
        case "restaurant", "dining", "food": return "fork.knife"
        case "attraction", "activity", "sight": return "star.fill"
        case "beach": return "beach.umbrella.fill"
        case "park", "hike", "trail": return "figure.hiking"
        case "airport": return "airplane"
        case "shopping": return "bag.fill"
        default: return "mappin.circle.fill"
        }
    }
}

/// Common place categories offered in the picker.
enum PlaceCategory {
    static let all = ["Hotel", "Restaurant", "Attraction", "Beach", "Park", "Shopping", "Airport", "Other"]
}
