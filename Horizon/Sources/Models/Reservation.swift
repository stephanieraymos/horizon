import Foundation

enum ReservationType: String, Codable, CaseIterable, Hashable {
    case flight, lodging, car, rail, ferry, dining, activity, themepark, event, other

    var label: String {
        switch self {
        case .flight: "Flight"; case .lodging: "Lodging"; case .car: "Car"
        case .rail: "Train"; case .ferry: "Ferry"; case .dining: "Dining"
        case .activity: "Activity"; case .themepark: "Theme Park"
        case .event: "Event"; case .other: "Other"
        }
    }

    var systemImage: String {
        switch self {
        case .flight: "airplane"; case .lodging: "bed.double"; case .car: "car"
        case .rail: "tram"; case .ferry: "ferry"; case .dining: "fork.knife"
        case .activity: "figure.hiking"; case .themepark: "sparkles"
        case .event: "ticket"; case .other: "mappin.and.ellipse"
        }
    }

    /// Labels for the generic start/end datetimes, contextual per type.
    var startLabel: String {
        switch self {
        case .flight: "Departs"; case .lodging: "Check-in"; case .car: "Pick-up"
        case .rail, .ferry: "Departs"; case .dining, .activity, .themepark, .event: "Starts"
        case .other: "Starts"
        }
    }

    var endLabel: String {
        switch self {
        case .flight: "Arrives"; case .lodging: "Check-out"; case .car: "Drop-off"
        case .rail, .ferry: "Arrives"; case .dining, .activity, .themepark, .event: "Ends"
        case .other: "Ends"
        }
    }

    /// Extra type-specific fields captured in `details` (key, human label).
    var detailFields: [(key: String, label: String)] {
        switch self {
        case .flight:
            return [("airline", "Airline"), ("flight_number", "Flight #"),
                    ("depart_airport", "From (airport)"), ("arrive_airport", "To (airport)")]
        case .lodging:
            return [("room", "Room / unit")]
        case .car:
            return [("company", "Company"), ("pickup", "Pick-up location"),
                    ("dropoff", "Drop-off location")]
        case .rail, .ferry:
            return [("carrier", "Carrier"), ("depart_station", "From"), ("arrive_station", "To")]
        default:
            return []
        }
    }
}

/// Mirror of `fam_reservations`. Generic fields cover every type; `details`
/// holds the type-specific extras (airline, flight number, etc.).
struct Reservation: Codable, Identifiable, Hashable {
    let id: UUID
    var familyID: UUID
    var tripID: UUID
    var type: ReservationType
    var title: String
    var confirmationNumber: String?
    var startAt: Date?
    var endAt: Date?
    var address: String?
    var mapsURL: String?
    var placeID: UUID?
    var costCents: Int?
    var details: [String: String]
    var notes: String?
    var sort: Int

    var costDollars: Double? { costCents.map { Double($0) / 100 } }

    enum CodingKeys: String, CodingKey {
        case id
        case familyID = "family_id"
        case tripID = "trip_id"
        case type, title
        case confirmationNumber = "confirmation_number"
        case startAt = "start_at"
        case endAt = "end_at"
        case address
        case mapsURL = "maps_url"
        case placeID = "place_id"
        case costCents = "cost_cents"
        case details, notes, sort
    }

    init(id: UUID = UUID(), familyID: UUID, tripID: UUID, type: ReservationType = .other,
         title: String = "", confirmationNumber: String? = nil, startAt: Date? = nil,
         endAt: Date? = nil, address: String? = nil, mapsURL: String? = nil,
         placeID: UUID? = nil, costCents: Int? = nil, details: [String: String] = [:],
         notes: String? = nil, sort: Int = 0) {
        self.id = id; self.familyID = familyID; self.tripID = tripID
        self.type = type; self.title = title; self.confirmationNumber = confirmationNumber
        self.startAt = startAt; self.endAt = endAt; self.address = address
        self.mapsURL = mapsURL; self.placeID = placeID; self.costCents = costCents
        self.details = details; self.notes = notes; self.sort = sort
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id      = try c.decode(UUID.self, forKey: .id)
        familyID = try c.decode(UUID.self, forKey: .familyID)
        tripID  = try c.decode(UUID.self, forKey: .tripID)
        type    = (try? c.decode(ReservationType.self, forKey: .type)) ?? .other
        title   = try c.decode(String.self, forKey: .title)
        confirmationNumber = try c.decodeIfPresent(String.self, forKey: .confirmationNumber)
        startAt = try c.decodeIfPresent(Date.self, forKey: .startAt)
        endAt   = try c.decodeIfPresent(Date.self, forKey: .endAt)
        address = try c.decodeIfPresent(String.self, forKey: .address)
        mapsURL = try c.decodeIfPresent(String.self, forKey: .mapsURL)
        placeID = try c.decodeIfPresent(UUID.self, forKey: .placeID)
        costCents = try c.decodeIfPresent(Int.self, forKey: .costCents)
        details = (try? c.decode([String: String].self, forKey: .details)) ?? [:]
        notes   = try c.decodeIfPresent(String.self, forKey: .notes)
        sort    = try c.decodeIfPresent(Int.self, forKey: .sort) ?? 0
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(familyID, forKey: .familyID)
        try c.encode(tripID, forKey: .tripID)
        try c.encode(type, forKey: .type)
        try c.encode(title, forKey: .title)
        try c.encodeIfPresent(confirmationNumber, forKey: .confirmationNumber)
        try c.encodeIfPresent(startAt, forKey: .startAt)
        try c.encodeIfPresent(endAt, forKey: .endAt)
        try c.encodeIfPresent(address, forKey: .address)
        try c.encodeIfPresent(mapsURL, forKey: .mapsURL)
        try c.encodeIfPresent(placeID, forKey: .placeID)
        try c.encodeIfPresent(costCents, forKey: .costCents)
        try c.encode(details, forKey: .details)
        try c.encodeIfPresent(notes, forKey: .notes)
        try c.encode(sort, forKey: .sort)
    }
}
