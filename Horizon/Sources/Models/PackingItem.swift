import Foundation

/// A packing category with an editable icon (mirror of `fam_packing_categories`).
struct PackingCategoryItem: Codable, Identifiable, Hashable {
    let id: UUID
    var familyID: UUID
    var name: String
    var icon: String
    var sort: Int

    enum CodingKeys: String, CodingKey {
        case id
        case familyID = "family_id"
        case name, icon, sort
    }

    init(id: UUID = UUID(), familyID: UUID, name: String, icon: String = "shippingbox", sort: Int = 0) {
        self.id = id; self.familyID = familyID; self.name = name; self.icon = icon; self.sort = sort
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        familyID = try c.decode(UUID.self, forKey: .familyID)
        name = try c.decode(String.self, forKey: .name)
        icon = try c.decodeIfPresent(String.self, forKey: .icon) ?? "shippingbox"
        sort = try c.decodeIfPresent(Int.self, forKey: .sort) ?? 0
    }
}

/// Mirror of `fam_trip_packing`. `memberID` is required; `category` is free text
/// (matched against fam_packing_categories for its icon).
struct PackingItem: Codable, Identifiable, Hashable {
    let id: UUID
    var tripID: UUID
    /// Owner of the item, or nil for "Everyone" (shared).
    var memberID: UUID?
    var item: String
    var checked: Bool
    var autoSuggested: Bool
    var category: String?

    enum CodingKeys: String, CodingKey {
        case id
        case tripID = "trip_id"
        case memberID = "member_id"
        case item, checked
        case autoSuggested = "auto_suggested"
        case category
    }

    init(id: UUID = UUID(), tripID: UUID, memberID: UUID?, item: String,
         checked: Bool = false, autoSuggested: Bool = false, category: String? = nil) {
        self.id = id; self.tripID = tripID; self.memberID = memberID
        self.item = item; self.checked = checked
        self.autoSuggested = autoSuggested; self.category = category
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        tripID = try c.decode(UUID.self, forKey: .tripID)
        memberID = try c.decodeIfPresent(UUID.self, forKey: .memberID)
        item = try c.decode(String.self, forKey: .item)
        checked = try c.decodeIfPresent(Bool.self, forKey: .checked) ?? false
        autoSuggested = try c.decodeIfPresent(Bool.self, forKey: .autoSuggested) ?? false
        category = try c.decodeIfPresent(String.self, forKey: .category)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(tripID, forKey: .tripID)
        try c.encodeIfPresent(memberID, forKey: .memberID)
        try c.encode(item, forKey: .item)
        try c.encode(checked, forKey: .checked)
        try c.encode(autoSuggested, forKey: .autoSuggested)
        try c.encodeIfPresent(category, forKey: .category)
    }
}
