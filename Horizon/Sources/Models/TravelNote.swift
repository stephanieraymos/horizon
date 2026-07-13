import Foundation

/// Reusable travel-knowledge note ("never stop in San Fernando") — a rich block
/// document with tags, not tied to a single trip. Mirror of `fam_travel_notes`.
struct TravelNote: Codable, Identifiable, Hashable {
    let id: UUID
    var familyID: UUID
    var title: String
    var content: [ContentBlock]
    var tags: [String]
    var placeID: UUID?
    var destinationID: UUID?
    var createdBy: UUID?
    var createdAt: Date?
    var updatedAt: Date?

    /// First non-empty text block, for list previews.
    var preview: String? {
        content.first { ($0.text?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false) }?.text
    }

    enum CodingKeys: String, CodingKey {
        case id
        case familyID = "family_id"
        case title, content, tags
        case placeID = "place_id"
        case destinationID = "destination_id"
        case createdBy = "created_by"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    init(id: UUID = UUID(), familyID: UUID, title: String = "", content: [ContentBlock] = [],
         tags: [String] = [], placeID: UUID? = nil, destinationID: UUID? = nil) {
        self.id = id; self.familyID = familyID; self.title = title; self.content = content
        self.tags = tags; self.placeID = placeID; self.destinationID = destinationID
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        familyID = try c.decode(UUID.self, forKey: .familyID)
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        content = try c.decodeIfPresent([ContentBlock].self, forKey: .content) ?? []
        tags = try c.decodeIfPresent([String].self, forKey: .tags) ?? []
        placeID = try c.decodeIfPresent(UUID.self, forKey: .placeID)
        destinationID = try c.decodeIfPresent(UUID.self, forKey: .destinationID)
        createdBy = try c.decodeIfPresent(UUID.self, forKey: .createdBy)
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt)
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(familyID, forKey: .familyID)
        try c.encode(title, forKey: .title)
        try c.encode(content, forKey: .content)
        try c.encode(tags, forKey: .tags)
        try c.encodeIfPresent(placeID, forKey: .placeID)
        try c.encodeIfPresent(destinationID, forKey: .destinationID)
        try c.encodeIfPresent(createdBy, forKey: .createdBy)
    }
}
