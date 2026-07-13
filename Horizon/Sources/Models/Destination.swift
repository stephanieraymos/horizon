import Foundation

/// Mirror of `fam_destinations`. Doubles as the bucket-list unit: a destination
/// with `isWishlist == true` (and typically no trips yet) is a "someday" place.
struct Destination: Codable, Identifiable, Hashable {
    let id: UUID
    var familyID: UUID
    var name: String
    var placeTag: String?
    var kind: String?
    var notes: String?
    var isWishlist: Bool
    var placeID: UUID?
    var coverPhotoURL: String?
    var createdAt: Date?
    var updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case familyID = "family_id"
        case name
        case placeTag = "place_tag"
        case kind, notes
        case isWishlist = "is_wishlist"
        case placeID = "place_id"
        case coverPhotoURL = "cover_photo_url"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    init(id: UUID = UUID(), familyID: UUID, name: String, placeTag: String? = nil,
         kind: String? = nil, notes: String? = nil, isWishlist: Bool = false,
         placeID: UUID? = nil, coverPhotoURL: String? = nil) {
        self.id = id; self.familyID = familyID; self.name = name
        self.placeTag = placeTag; self.kind = kind; self.notes = notes
        self.isWishlist = isWishlist; self.placeID = placeID
        self.coverPhotoURL = coverPhotoURL
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id           = try c.decode(UUID.self, forKey: .id)
        familyID     = try c.decode(UUID.self, forKey: .familyID)
        name         = try c.decode(String.self, forKey: .name)
        placeTag     = try c.decodeIfPresent(String.self, forKey: .placeTag)
        kind         = try c.decodeIfPresent(String.self, forKey: .kind)
        notes        = try c.decodeIfPresent(String.self, forKey: .notes)
        isWishlist   = try c.decodeIfPresent(Bool.self, forKey: .isWishlist) ?? false
        placeID      = try c.decodeIfPresent(UUID.self, forKey: .placeID)
        coverPhotoURL = try c.decodeIfPresent(String.self, forKey: .coverPhotoURL)
        createdAt    = try c.decodeIfPresent(Date.self, forKey: .createdAt)
        updatedAt    = try c.decodeIfPresent(Date.self, forKey: .updatedAt)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(familyID, forKey: .familyID)
        try c.encode(name, forKey: .name)
        try c.encodeIfPresent(placeTag, forKey: .placeTag)
        try c.encodeIfPresent(kind, forKey: .kind)
        try c.encodeIfPresent(notes, forKey: .notes)
        try c.encode(isWishlist, forKey: .isWishlist)
        try c.encodeIfPresent(placeID, forKey: .placeID)
        try c.encodeIfPresent(coverPhotoURL, forKey: .coverPhotoURL)
    }
}
