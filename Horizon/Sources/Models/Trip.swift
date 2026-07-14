import Foundation

enum TripStatus: String, Codable, CaseIterable, Hashable {
    case planning
    case booked
    case inProgress = "in_progress"
    case done

    var label: String {
        switch self {
        case .planning:   return "Planning"
        case .booked:     return "Booked"
        case .inProgress: return "In Progress"
        case .done:       return "Done"
        }
    }

    var systemImage: String {
        switch self {
        case .planning:   return "pencil.and.list.clipboard"
        case .booked:     return "checkmark.seal"
        case .inProgress: return "airplane.departure"
        case .done:       return "flag.checkered"
        }
    }
}

/// Mirror of `fam_trips`. A trip with no `departDate` is a "someday" / TBD trip
/// (the bucket-list layer). `status` values stay compatible with TheGlade's
/// decoder — someday-ness is expressed by absent dates, not a new status value.
struct Trip: Codable, Identifiable, Hashable {
    let id: UUID
    var familyID: UUID
    var name: String
    var destination: String?
    var destinationID: UUID?
    var departDate: Date?
    var returnDate: Date?
    var travelers: [String]?
    var coverPhotoURL: String?
    var transportation: String?
    var status: TripStatus
    var budget: Double?
    var placeID: UUID?
    /// "Not going" — hidden from the main lists, restorable.
    var archived: Bool
    var createdBy: UUID?
    var createdAt: Date?
    var updatedAt: Date?
    /// Rich-text notes document. Decode-only here; saved via TripsStore.saveTripNotes
    /// so a plain trip upsert never clobbers it.
    var notesContent: [ContentBlock]?

    // MARK: Derived

    var isSomeday: Bool { departDate == nil }

    /// End of the trip for past/upcoming bucketing (return date, else depart).
    private var endReference: Date? { returnDate ?? departDate }

    var isPast: Bool {
        guard let end = endReference else { return false }
        return end < Calendar.current.startOfDay(for: Date())
    }

    var isUpcoming: Bool { !isSomeday && !isPast }

    /// Whole days from today until departure (negative if already departed).
    var daysUntilDeparture: Int? {
        guard let depart = departDate else { return nil }
        let cal = Calendar.current
        return cal.dateComponents([.day], from: cal.startOfDay(for: Date()),
                                  to: cal.startOfDay(for: depart)).day
    }

    var nights: Int? {
        guard let a = departDate, let b = returnDate else { return nil }
        return Calendar.current.dateComponents([.day], from: a, to: b).day
    }

    /// Short human countdown for lists and the detail header.
    var countdownText: String {
        if isSomeday { return "Someday" }
        guard let days = daysUntilDeparture else { return "" }
        if let end = returnDate, days <= 0,
           end >= Calendar.current.startOfDay(for: Date()) { return "Now" }
        if days < 0 { return departDate.map { Self.yearFormatter.string(from: $0) } ?? "" }
        if days == 0 { return "Today" }
        if days == 1 { return "Tomorrow" }
        if days < 30 { return "in \(days) days" }
        let weeks = days / 7
        if days < 60 { return "in \(weeks) weeks" }
        let months = days / 30
        return "in \(months) months"
    }

    static let yearFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy"; return f
    }()

    // MARK: Codable

    enum CodingKeys: String, CodingKey {
        case id
        case familyID = "family_id"
        case name, destination
        case destinationID = "destination_id"
        case departDate = "depart_date"
        case returnDate = "return_date"
        case travelers
        case coverPhotoURL = "cover_photo_url"
        case transportation, status, budget
        case placeID = "place_id"
        case archived
        case createdBy = "created_by"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case notesContent = "notes_content"
    }

    init(id: UUID = UUID(), familyID: UUID, name: String, destination: String? = nil,
         destinationID: UUID? = nil, departDate: Date? = nil, returnDate: Date? = nil,
         travelers: [String]? = nil, coverPhotoURL: String? = nil, transportation: String? = nil,
         status: TripStatus = .planning, budget: Double? = nil, placeID: UUID? = nil,
         archived: Bool = false, createdBy: UUID? = nil) {
        self.id = id; self.familyID = familyID; self.name = name
        self.destination = destination; self.destinationID = destinationID
        self.departDate = departDate; self.returnDate = returnDate
        self.travelers = travelers; self.coverPhotoURL = coverPhotoURL
        self.transportation = transportation; self.status = status
        self.budget = budget; self.placeID = placeID; self.archived = archived
        self.createdBy = createdBy
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id            = try c.decode(UUID.self, forKey: .id)
        familyID      = try c.decode(UUID.self, forKey: .familyID)
        name          = try c.decode(String.self, forKey: .name)
        destination   = try c.decodeIfPresent(String.self, forKey: .destination)
        destinationID = try c.decodeIfPresent(UUID.self, forKey: .destinationID)
        departDate    = try decodeDateOnlyIfPresent(c, forKey: .departDate)
        returnDate    = try decodeDateOnlyIfPresent(c, forKey: .returnDate)
        travelers     = try c.decodeIfPresent([String].self, forKey: .travelers)
        coverPhotoURL = try c.decodeIfPresent(String.self, forKey: .coverPhotoURL)
        transportation = try c.decodeIfPresent(String.self, forKey: .transportation)
        status        = (try? c.decode(TripStatus.self, forKey: .status)) ?? .planning
        budget        = try c.decodeIfPresent(Double.self, forKey: .budget)
        placeID       = try c.decodeIfPresent(UUID.self, forKey: .placeID)
        archived      = try c.decodeIfPresent(Bool.self, forKey: .archived) ?? false
        createdBy     = try c.decodeIfPresent(UUID.self, forKey: .createdBy)
        createdAt     = try c.decodeIfPresent(Date.self, forKey: .createdAt)
        updatedAt     = try c.decodeIfPresent(Date.self, forKey: .updatedAt)
        notesContent  = try c.decodeIfPresent([ContentBlock].self, forKey: .notesContent)
    }

    /// Encodes only the writable columns (for upsert). Timestamps and created_by
    /// are left to the database defaults.
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(familyID, forKey: .familyID)
        try c.encode(name, forKey: .name)
        try c.encodeIfPresent(destination, forKey: .destination)
        try c.encodeIfPresent(destinationID, forKey: .destinationID)
        if let departDate { try encodeDateOnly(&c, departDate, forKey: .departDate) }
        else { try c.encodeNil(forKey: .departDate) }
        if let returnDate { try encodeDateOnly(&c, returnDate, forKey: .returnDate) }
        else { try c.encodeNil(forKey: .returnDate) }
        try c.encodeIfPresent(travelers, forKey: .travelers)
        try c.encodeIfPresent(coverPhotoURL, forKey: .coverPhotoURL)
        try c.encodeIfPresent(transportation, forKey: .transportation)
        try c.encode(status, forKey: .status)
        try c.encodeIfPresent(budget, forKey: .budget)
        try c.encodeIfPresent(placeID, forKey: .placeID)
        try c.encode(archived, forKey: .archived)
    }
}
