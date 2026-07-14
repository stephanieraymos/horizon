import Foundation

/// A dated family milestone with a live day-away countdown — birthdays,
/// anniversaries, vacations, holidays, and one-off events. Shares the
/// `fam_events` table with TheGlade on the same backend; unknown columns
/// (cover_photo_url, album_id) decode harmlessly.
struct FamilyEvent: Codable, Identifiable, Hashable {
    let id: UUID
    let familyID: UUID
    var title: String
    var eventType: String?
    var eventDate: Date
    var isAnnual: Bool
    var description: String?
    var emoji: String?
    var coverPhotoURL: String?
    var members: [String]?
    var albumID: UUID?
    var createdBy: UUID?
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case familyID = "family_id"
        case title
        case eventType = "event_type"
        case eventDate = "event_date"
        case isAnnual = "is_annual"
        case description, emoji
        case coverPhotoURL = "cover_photo_url"
        case members
        case albumID = "album_id"
        case createdBy = "created_by"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id            = try c.decode(UUID.self, forKey: .id)
        familyID      = try c.decode(UUID.self, forKey: .familyID)
        title         = try c.decode(String.self, forKey: .title)
        eventType     = try c.decodeIfPresent(String.self, forKey: .eventType)
        eventDate     = try decodeDateOnly(c, forKey: .eventDate)
        isAnnual      = (try? c.decode(Bool.self, forKey: .isAnnual)) ?? false
        description   = try c.decodeIfPresent(String.self, forKey: .description)
        emoji         = try c.decodeIfPresent(String.self, forKey: .emoji)
        coverPhotoURL = try c.decodeIfPresent(String.self, forKey: .coverPhotoURL)
        members       = try c.decodeIfPresent([String].self, forKey: .members)
        albumID       = try c.decodeIfPresent(UUID.self, forKey: .albumID)
        createdBy     = try c.decodeIfPresent(UUID.self, forKey: .createdBy)
        createdAt     = try c.decode(Date.self, forKey: .createdAt)
        updatedAt     = try c.decode(Date.self, forKey: .updatedAt)
    }

    // MARK: - Memberwise init (for synthesized / in-memory events)

    init(
        id: UUID,
        familyID: UUID,
        title: String,
        eventType: String? = nil,
        eventDate: Date,
        isAnnual: Bool = false,
        description: String? = nil,
        emoji: String? = nil,
        coverPhotoURL: String? = nil,
        members: [String]? = nil,
        albumID: UUID? = nil,
        createdBy: UUID? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id            = id
        self.familyID      = familyID
        self.title         = title
        self.eventType     = eventType
        self.eventDate     = eventDate
        self.isAnnual      = isAnnual
        self.description   = description
        self.emoji         = emoji
        self.coverPhotoURL = coverPhotoURL
        self.members       = members
        self.albumID       = albumID
        self.createdBy     = createdBy
        self.createdAt     = createdAt
        self.updatedAt     = updatedAt
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(familyID, forKey: .familyID)
        try c.encode(title, forKey: .title)
        try c.encodeIfPresent(eventType, forKey: .eventType)
        try encodeDateOnly(&c, eventDate, forKey: .eventDate)
        try c.encode(isAnnual, forKey: .isAnnual)
        try c.encodeIfPresent(description, forKey: .description)
        try c.encodeIfPresent(emoji, forKey: .emoji)
        try c.encodeIfPresent(coverPhotoURL, forKey: .coverPhotoURL)
        try c.encodeIfPresent(members, forKey: .members)
        try c.encodeIfPresent(albumID, forKey: .albumID)
        try c.encodeIfPresent(createdBy, forKey: .createdBy)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encode(updatedAt, forKey: .updatedAt)
    }

    // MARK: - Computed

    /// For annual events: next upcoming occurrence of this month+day.
    /// For one-time events: the event date itself.
    var nextOccurrenceDate: Date {
        guard isAnnual else { return eventDate }
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        var comps = cal.dateComponents([.month, .day], from: eventDate)
        comps.year = cal.component(.year, from: today)
        if let candidate = cal.date(from: comps), candidate >= today {
            return candidate
        }
        comps.year = (comps.year ?? cal.component(.year, from: today)) + 1
        return cal.date(from: comps) ?? eventDate
    }

    /// Whole-day distance from today to the event's next display date.
    /// Uses nextOccurrenceDate for annual events so the countdown always
    /// points forward.
    var daysAway: Int {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let target = cal.startOfDay(for: isAnnual ? nextOccurrenceDate : eventDate)
        return cal.dateComponents([.day], from: today, to: target).day ?? 0
    }

    /// How many years will have elapsed at the next occurrence.
    /// e.g. born Oct 7 1992 → turns 33 in 2025.
    /// Returns nil for non-annual events or when the result would be ≤ 0.
    var yearsAtNextOccurrence: Int? {
        guard isAnnual else { return nil }
        let cal = Calendar.current
        let originYear = cal.component(.year, from: eventDate)
        let nextYear   = cal.component(.year, from: nextOccurrenceDate)
        let years = nextYear - originYear
        return years > 0 ? years : nil
    }
}

// MARK: - Event types

enum FamilyEventType: String, CaseIterable {
    case birthday    = "Birthday"
    case anniversary = "Anniversary"
    case vacation    = "Vacation"
    case holiday     = "Holiday"
    case outing      = "Outing"
    case school      = "School Event"
    case milestone   = "Milestone"
    case other       = "Other"

    /// Types that auto-repeat every year and benefit from start-year tracking.
    static var annualTypes: Set<String> {
        [birthday.rawValue, anniversary.rawValue]
    }
}
