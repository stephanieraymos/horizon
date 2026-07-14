import Foundation

/// A photo collection that can be attached to a trip (or, in TheGlade, an event
/// or date night). Horizon uses one album per trip as its mood board, reusing
/// the shared `fam_albums` table (already carries `trip_id`).
struct Album: Codable, Identifiable, Hashable {
    let id: UUID
    let familyID: UUID
    var name: String
    var category: String?
    var coverPhotoURL: String?
    var tripID: UUID?
    var eventID: UUID?
    var dateNightID: UUID?
    var createdBy: UUID?
    let createdAt: Date
    let updatedAt: Date

    init(id: UUID = UUID(), familyID: UUID, name: String, category: String? = nil,
         coverPhotoURL: String? = nil, tripID: UUID? = nil, eventID: UUID? = nil,
         dateNightID: UUID? = nil, createdBy: UUID? = nil,
         createdAt: Date = Date(), updatedAt: Date = Date()) {
        self.id = id; self.familyID = familyID; self.name = name; self.category = category
        self.coverPhotoURL = coverPhotoURL; self.tripID = tripID; self.eventID = eventID
        self.dateNightID = dateNightID; self.createdBy = createdBy
        self.createdAt = createdAt; self.updatedAt = updatedAt
    }

    enum CodingKeys: String, CodingKey {
        case id
        case familyID       = "family_id"
        case name, category
        case coverPhotoURL  = "cover_photo_url"
        case tripID         = "trip_id"
        case eventID        = "event_id"
        case dateNightID    = "date_night_id"
        case createdBy      = "created_by"
        case createdAt      = "created_at"
        case updatedAt      = "updated_at"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id            = try c.decode(UUID.self, forKey: .id)
        familyID      = try c.decode(UUID.self, forKey: .familyID)
        name          = try c.decode(String.self, forKey: .name)
        category      = try c.decodeIfPresent(String.self, forKey: .category)
        coverPhotoURL = try c.decodeIfPresent(String.self, forKey: .coverPhotoURL)
        tripID        = try c.decodeIfPresent(UUID.self, forKey: .tripID)
        eventID       = try c.decodeIfPresent(UUID.self, forKey: .eventID)
        dateNightID   = try c.decodeIfPresent(UUID.self, forKey: .dateNightID)
        createdBy     = try c.decodeIfPresent(UUID.self, forKey: .createdBy)
        createdAt     = try c.decode(Date.self, forKey: .createdAt)
        updatedAt     = try c.decode(Date.self, forKey: .updatedAt)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(familyID, forKey: .familyID)
        try c.encode(name, forKey: .name)
        try c.encodeIfPresent(category, forKey: .category)
        try c.encodeIfPresent(coverPhotoURL, forKey: .coverPhotoURL)
        try c.encodeIfPresent(tripID, forKey: .tripID)
        try c.encodeIfPresent(eventID, forKey: .eventID)
        try c.encodeIfPresent(dateNightID, forKey: .dateNightID)
        try c.encodeIfPresent(createdBy, forKey: .createdBy)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encode(updatedAt, forKey: .updatedAt)
    }
}

/// One photo entry in an album. Horizon writes one photo per row (single entry
/// in `photoURLs`) so `tag` + `addedBy` are effectively per-photo for the mood
/// board's filters. Legacy TheGlade rows may carry multiple URLs.
struct Memory: Codable, Identifiable, Hashable {
    let id: UUID
    let familyID: UUID
    let albumID: UUID
    var caption: String?
    var photoURLs: [String]
    var takenAt: Date?
    var location: String?
    var addedBy: UUID?
    /// Free-text label for filtering the mood board (e.g. "food", "views").
    var tag: String?
    let createdAt: Date

    init(id: UUID, familyID: UUID, albumID: UUID, caption: String?, photoURLs: [String],
         takenAt: Date?, location: String?, addedBy: UUID?, tag: String?, createdAt: Date) {
        self.id = id; self.familyID = familyID; self.albumID = albumID
        self.caption = caption; self.photoURLs = photoURLs; self.takenAt = takenAt
        self.location = location; self.addedBy = addedBy; self.tag = tag; self.createdAt = createdAt
    }

    enum CodingKeys: String, CodingKey {
        case id
        case familyID = "family_id"
        case albumID = "album_id"
        case caption
        case photoURLs = "photo_urls"
        case takenAt = "taken_at"
        case location
        case addedBy = "added_by"
        case tag
        case createdAt = "created_at"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id        = try c.decode(UUID.self, forKey: .id)
        familyID  = try c.decode(UUID.self, forKey: .familyID)
        albumID   = try c.decode(UUID.self, forKey: .albumID)
        caption   = try c.decodeIfPresent(String.self, forKey: .caption)
        photoURLs = try c.decodeIfPresent([String].self, forKey: .photoURLs) ?? []
        takenAt   = try decodeDateOnlyIfPresent(c, forKey: .takenAt)
        location  = try c.decodeIfPresent(String.self, forKey: .location)
        addedBy   = try c.decodeIfPresent(UUID.self, forKey: .addedBy)
        tag       = try c.decodeIfPresent(String.self, forKey: .tag)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(familyID, forKey: .familyID)
        try c.encode(albumID, forKey: .albumID)
        try c.encodeIfPresent(caption, forKey: .caption)
        try c.encode(photoURLs, forKey: .photoURLs)
        if let takenAt { try encodeDateOnly(&c, takenAt, forKey: .takenAt) }
        try c.encodeIfPresent(location, forKey: .location)
        try c.encodeIfPresent(addedBy, forKey: .addedBy)
        try c.encodeIfPresent(tag, forKey: .tag)
        try c.encode(createdAt, forKey: .createdAt)
    }
}

/// A single displayable photo, flattened from a `Memory` (which may hold more
/// than one URL for legacy rows). Carries the parent memory's tag/uploader.
struct MoodPhoto: Identifiable, Hashable {
    let id: String          // stable: memoryID + url index
    let url: String
    let tag: String?
    let addedBy: UUID?
    let memoryID: UUID
    let caption: String?
}
