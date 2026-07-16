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
    /// Set when this activity was auto-generated from a reservation's check-in /
    /// check-out, so it can be updated/removed in sync when the reservation
    /// changes. Additive JSON key — other apps sharing the table ignore it.
    var reservationID: UUID?
    /// Manual display order within its day. nil = "auto" (order by time); set once
    /// the user drags to reorder. Additive JSON key.
    var sort: Int?

    enum CodingKeys: String, CodingKey {
        case id, time, title
        case locationName = "location_name"
        case mapsURL = "maps_url"
        case notes, done
        case reservationID = "reservation_id"
        case sort
    }
}

/// Time parsing/formatting for itinerary activities. Stored `time` may be any
/// legacy format ("2:00pm", "14:00") or the current "h:mm a"; these normalize it.
enum ItineraryTime {
    private static func formatter(_ fmt: String) -> DateFormatter {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = fmt; return f
    }
    static func parse(_ s: String?) -> Date? {
        guard let s = s?.trimmingCharacters(in: .whitespaces), !s.isEmpty else { return nil }
        for fmt in ["h:mm a", "h:mma", "HH:mm", "H:mm"] {
            if let d = formatter(fmt).date(from: s) { return d }
        }
        return nil
    }
    static func format(_ date: Date) -> String { formatter("h:mm a").string(from: date) }
    /// Consistent "h:mm a" for display; nil for all-day / blank / unparseable.
    static func display(_ s: String?) -> String? { parse(s).map(format) }
    /// Minutes since midnight for sorting; all-day/unparseable sorts first.
    static func sortValue(_ s: String?) -> Int {
        guard let d = parse(s) else { return -1 }
        let c = Calendar.current.dateComponents([.hour, .minute], from: d)
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }
}

/// One activity flattened out of its day row, keeping a link back to the row it
/// lives in (multiple rows can share a date; the timeline merges them).
struct ItineraryEntry: Identifiable {
    let activity: ItineraryActivity
    let dayID: UUID
    var id: UUID { activity.id }
}

/// A calendar day's worth of activities for the timeline, time-sorted.
struct ItineraryDayGroup: Identifiable {
    let date: Date
    let entries: [ItineraryEntry]
    var id: Date { date }
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
