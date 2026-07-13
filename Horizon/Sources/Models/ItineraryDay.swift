import Foundation

/// One scheduled activity within a day. JSON keys match TheGlade exactly
/// (`location_name`, `maps_url`) so the shared `fam_trip_itinerary.activities`
/// jsonb stays decodable by both apps. `done` is additive — Glade ignores it.
struct ItineraryActivity: Codable, Hashable, Identifiable {
    var id: UUID = UUID()
    var time: String?          // "HH:MM" or nil for all-day
    var title: String
    var locationName: String?
    var mapsURL: String?
    var notes: String?
    var done: Bool?

    enum CodingKeys: String, CodingKey {
        case id, time, title
        case locationName = "location_name"
        case mapsURL = "maps_url"
        case notes, done
    }
}

/// Mirror of `fam_trip_itinerary` (one row per day; activities as a jsonb array).
struct ItineraryDay: Codable, Identifiable, Hashable {
    let id: UUID
    var tripID: UUID
    var dayDate: Date
    var activities: [ItineraryActivity]

    enum CodingKeys: String, CodingKey {
        case id
        case tripID = "trip_id"
        case dayDate = "day_date"
        case activities
    }

    init(id: UUID = UUID(), tripID: UUID, dayDate: Date, activities: [ItineraryActivity] = []) {
        self.id = id; self.tripID = tripID; self.dayDate = dayDate; self.activities = activities
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        tripID = try c.decode(UUID.self, forKey: .tripID)
        dayDate = try decodeDateOnly(c, forKey: .dayDate)
        activities = try c.decodeIfPresent([ItineraryActivity].self, forKey: .activities) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(tripID, forKey: .tripID)
        try encodeDateOnly(&c, dayDate, forKey: .dayDate)
        try c.encode(activities, forKey: .activities)
    }
}
