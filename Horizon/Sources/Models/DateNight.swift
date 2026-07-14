import Foundation

// MARK: - Destination stop

/// A single location stop on a date (restaurant, venue, etc.). Stored inline
/// as JSON on the date row; the name/address/mapsURL also feed the shared
/// `fam_places` library.
struct DateNightDestination: Codable, Identifiable, Hashable {
    var id: UUID
    var name: String
    var address: String?
    var mapsURL: String?

    init(id: UUID = UUID(), name: String, address: String? = nil, mapsURL: String? = nil) {
        self.id = id
        self.name = name
        self.address = address
        self.mapsURL = mapsURL
    }

    enum CodingKeys: String, CodingKey {
        case id, name, address
        case mapsURL = "maps_url"
    }
}

// MARK: - DateNight

/// A planned or completed date, from a saved idea → scheduled outing → rated
/// memory. Shares the `fam_dates` table with TheGlade on the same backend.
/// `movieID` (TheGlade's movie-date link) is preserved on round-trip but has
/// no UI in Horizon.
struct DateNight: Codable, Identifiable, Hashable {
    let id: UUID
    let familyID: UUID
    var title: String
    var category: String?
    /// Multi-stop destinations list. Each entry is a `DateNightDestination`
    /// (name + optional address + optional maps URL).
    var destinations: [DateNightDestination]?
    var estCost: Double?
    var notes: String?
    var ideaOnly: Bool
    var scheduledAt: Date?
    var rating: Int?
    var reviewNotes: String?
    var photoURL: String?
    /// TheGlade-only link to a movie in the watch list. Preserved on save so
    /// editing a movie-date in Horizon doesn't drop the link.
    var movieID: UUID?
    var createdBy: UUID?
    let createdAt: Date
    let updatedAt: Date

    /// Past = was scheduled AND scheduled time has passed.
    var isPast: Bool {
        guard let scheduledAt else { return false }
        return scheduledAt < Date()
    }

    /// Best display name for the location — the first destination's name.
    var primaryLocationName: String? {
        destinations?.first?.name
    }

    /// Primary maps URL for notification body text.
    var primaryMapsURL: String? {
        destinations?.first?.mapsURL
    }

    enum CodingKeys: String, CodingKey {
        case id
        case familyID = "family_id"
        case title, category
        case destinations
        case estCost = "est_cost"
        case notes
        case ideaOnly = "idea_only"
        case scheduledAt = "scheduled_at"
        case rating
        case reviewNotes = "review_notes"
        case photoURL = "photo_url"
        case movieID = "movie_id"
        case createdBy = "created_by"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    init(
        id: UUID,
        familyID: UUID,
        title: String,
        category: String?,
        destinations: [DateNightDestination]? = nil,
        estCost: Double?,
        notes: String?,
        ideaOnly: Bool,
        scheduledAt: Date?,
        rating: Int?,
        reviewNotes: String?,
        photoURL: String?,
        movieID: UUID? = nil,
        createdBy: UUID?,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.familyID = familyID
        self.title = title
        self.category = category
        self.destinations = destinations
        self.estCost = estCost
        self.notes = notes
        self.ideaOnly = ideaOnly
        self.scheduledAt = scheduledAt
        self.rating = rating
        self.reviewNotes = reviewNotes
        self.photoURL = photoURL
        self.movieID = movieID
        self.createdBy = createdBy
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id              = try c.decode(UUID.self, forKey: .id)
        familyID        = try c.decode(UUID.self, forKey: .familyID)
        title           = try c.decode(String.self, forKey: .title)
        category        = try c.decodeIfPresent(String.self, forKey: .category)
        destinations    = try c.decodeIfPresent([DateNightDestination].self, forKey: .destinations)
        estCost         = try c.decodeIfPresent(Double.self, forKey: .estCost)
        notes           = try c.decodeIfPresent(String.self, forKey: .notes)
        ideaOnly        = try c.decodeIfPresent(Bool.self, forKey: .ideaOnly) ?? true
        scheduledAt     = try c.decodeIfPresent(Date.self, forKey: .scheduledAt)
        rating          = try c.decodeIfPresent(Int.self, forKey: .rating)
        reviewNotes     = try c.decodeIfPresent(String.self, forKey: .reviewNotes)
        photoURL        = try c.decodeIfPresent(String.self, forKey: .photoURL)
        movieID         = try c.decodeIfPresent(UUID.self, forKey: .movieID)
        createdBy       = try c.decodeIfPresent(UUID.self, forKey: .createdBy)
        createdAt       = try c.decode(Date.self, forKey: .createdAt)
        updatedAt       = try c.decode(Date.self, forKey: .updatedAt)
    }
}

enum DateNightCategory: String, CaseIterable {
    case dinner = "Dinner"
    case activity = "Activity"
    case stayIn = "Stay-in"
    case adventure = "Adventure"
}
