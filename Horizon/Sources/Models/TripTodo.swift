import Foundation

/// A pre-trip checklist task (renew passport, book rental, arrange pet sitter),
/// distinct from packing. Mirror of `fam_trip_todos`.
struct TripTodo: Codable, Identifiable, Hashable {
    let id: UUID
    var tripID: UUID
    var familyID: UUID
    var title: String
    var done: Bool
    var dueDate: Date?
    var sort: Int
    var createdBy: UUID?

    enum CodingKeys: String, CodingKey {
        case id
        case tripID = "trip_id"
        case familyID = "family_id"
        case title, done
        case dueDate = "due_date"
        case sort
        case createdBy = "created_by"
    }

    init(id: UUID = UUID(), tripID: UUID, familyID: UUID, title: String,
         done: Bool = false, dueDate: Date? = nil, sort: Int = 0, createdBy: UUID? = nil) {
        self.id = id; self.tripID = tripID; self.familyID = familyID; self.title = title
        self.done = done; self.dueDate = dueDate; self.sort = sort; self.createdBy = createdBy
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        tripID = try c.decode(UUID.self, forKey: .tripID)
        familyID = try c.decode(UUID.self, forKey: .familyID)
        title = try c.decode(String.self, forKey: .title)
        done = try c.decodeIfPresent(Bool.self, forKey: .done) ?? false
        dueDate = try decodeDateOnlyIfPresent(c, forKey: .dueDate)
        sort = try c.decodeIfPresent(Int.self, forKey: .sort) ?? 0
        createdBy = try c.decodeIfPresent(UUID.self, forKey: .createdBy)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(tripID, forKey: .tripID)
        try c.encode(familyID, forKey: .familyID)
        try c.encode(title, forKey: .title)
        try c.encode(done, forKey: .done)
        if let dueDate { try encodeDateOnly(&c, dueDate, forKey: .dueDate) }
        try c.encode(sort, forKey: .sort)
        try c.encodeIfPresent(createdBy, forKey: .createdBy)
    }
}
