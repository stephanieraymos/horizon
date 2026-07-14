import Foundation

/// Minimal mirror of `fam_places` for the location combobox.
struct Place: Codable, Identifiable, Hashable {
    let id: UUID
    var familyID: UUID
    var name: String
    var category: String?
    var address: String?
    var mapsURL: String?
    var notes: String?
    var visited: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case familyID = "family_id"
        case name, category, address
        case mapsURL = "maps_url"
        case notes, visited
    }

    init(id: UUID = UUID(), familyID: UUID, name: String, category: String? = nil,
         address: String? = nil, mapsURL: String? = nil, notes: String? = nil, visited: Bool = false) {
        self.id = id; self.familyID = familyID; self.name = name; self.category = category
        self.address = address; self.mapsURL = mapsURL; self.notes = notes; self.visited = visited
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        familyID = try c.decode(UUID.self, forKey: .familyID)
        name = try c.decode(String.self, forKey: .name)
        category = try c.decodeIfPresent(String.self, forKey: .category)
        address = try c.decodeIfPresent(String.self, forKey: .address)
        mapsURL = try c.decodeIfPresent(String.self, forKey: .mapsURL)
        notes = try c.decodeIfPresent(String.self, forKey: .notes)
        visited = try c.decodeIfPresent(Bool.self, forKey: .visited) ?? false
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(familyID, forKey: .familyID)
        try c.encode(name, forKey: .name)
        try c.encodeIfPresent(category, forKey: .category)
        try c.encodeIfPresent(address, forKey: .address)
        try c.encodeIfPresent(mapsURL, forKey: .mapsURL)
        try c.encodeIfPresent(notes, forKey: .notes)
        try c.encode(visited, forKey: .visited)
    }
}
