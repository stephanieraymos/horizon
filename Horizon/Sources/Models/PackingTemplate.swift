import Foundation

/// A reusable packing list (Beach, Disneyland, …). Family-level; applying it to
/// a trip copies its items into that trip's packing list for chosen travelers.
struct PackingTemplate: Codable, Identifiable, Hashable {
    let id: UUID
    var familyID: UUID
    var name: String
    var icon: String
    var createdBy: UUID?

    enum CodingKeys: String, CodingKey {
        case id
        case familyID = "family_id"
        case name, icon
        case createdBy = "created_by"
    }

    init(id: UUID = UUID(), familyID: UUID, name: String, icon: String = "suitcase.fill", createdBy: UUID? = nil) {
        self.id = id; self.familyID = familyID; self.name = name; self.icon = icon; self.createdBy = createdBy
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        familyID = try c.decode(UUID.self, forKey: .familyID)
        name = try c.decode(String.self, forKey: .name)
        icon = try c.decodeIfPresent(String.self, forKey: .icon) ?? "suitcase.fill"
        createdBy = try c.decodeIfPresent(UUID.self, forKey: .createdBy)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(familyID, forKey: .familyID)
        try c.encode(name, forKey: .name)
        try c.encode(icon, forKey: .icon)
        try c.encodeIfPresent(createdBy, forKey: .createdBy)
    }
}

/// One line in a packing template (item + optional category, no member).
struct PackingTemplateItem: Codable, Identifiable, Hashable {
    let id: UUID
    var templateID: UUID
    var item: String
    var category: String?
    var sort: Int

    enum CodingKeys: String, CodingKey {
        case id
        case templateID = "template_id"
        case item, category, sort
    }

    init(id: UUID = UUID(), templateID: UUID, item: String, category: String? = nil, sort: Int = 0) {
        self.id = id; self.templateID = templateID; self.item = item; self.category = category; self.sort = sort
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        templateID = try c.decode(UUID.self, forKey: .templateID)
        item = try c.decode(String.self, forKey: .item)
        category = try c.decodeIfPresent(String.self, forKey: .category)
        sort = try c.decodeIfPresent(Int.self, forKey: .sort) ?? 0
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(templateID, forKey: .templateID)
        try c.encode(item, forKey: .item)
        try c.encodeIfPresent(category, forKey: .category)
        try c.encode(sort, forKey: .sort)
    }
}
