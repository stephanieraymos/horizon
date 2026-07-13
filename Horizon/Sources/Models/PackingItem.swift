import Foundation

enum PackingCategory: String, Codable, CaseIterable, Hashable {
    case clothes, bathroom, tech, documents, snacks, kids, gear, other

    var label: String {
        switch self {
        case .clothes: "Clothes"; case .bathroom: "Bathroom"; case .tech: "Tech"
        case .documents: "Documents"; case .snacks: "Snacks"; case .kids: "Kids"
        case .gear: "Gear"; case .other: "Other"
        }
    }

    var systemImage: String {
        switch self {
        case .clothes: "tshirt"; case .bathroom: "shower"; case .tech: "laptopcomputer"
        case .documents: "doc.text"; case .snacks: "takeoutbag.and.cup.and.straw"
        case .kids: "figure.and.child.holdinghands"; case .gear: "backpack"; case .other: "shippingbox"
        }
    }
}

/// Mirror of `fam_trip_packing`. `memberID` is required (matches Glade);
/// `category` is the additive Phase-3 column (Glade ignores it).
struct PackingItem: Codable, Identifiable, Hashable {
    let id: UUID
    var tripID: UUID
    var memberID: UUID
    var item: String
    var checked: Bool
    var autoSuggested: Bool
    var category: PackingCategory?

    enum CodingKeys: String, CodingKey {
        case id
        case tripID = "trip_id"
        case memberID = "member_id"
        case item, checked
        case autoSuggested = "auto_suggested"
        case category
    }

    init(id: UUID = UUID(), tripID: UUID, memberID: UUID, item: String,
         checked: Bool = false, autoSuggested: Bool = false, category: PackingCategory? = nil) {
        self.id = id; self.tripID = tripID; self.memberID = memberID
        self.item = item; self.checked = checked
        self.autoSuggested = autoSuggested; self.category = category
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        tripID = try c.decode(UUID.self, forKey: .tripID)
        memberID = try c.decode(UUID.self, forKey: .memberID)
        item = try c.decode(String.self, forKey: .item)
        checked = try c.decodeIfPresent(Bool.self, forKey: .checked) ?? false
        autoSuggested = try c.decodeIfPresent(Bool.self, forKey: .autoSuggested) ?? false
        category = try c.decodeIfPresent(PackingCategory.self, forKey: .category)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(tripID, forKey: .tripID)
        try c.encode(memberID, forKey: .memberID)
        try c.encode(item, forKey: .item)
        try c.encode(checked, forKey: .checked)
        try c.encode(autoSuggested, forKey: .autoSuggested)
        try c.encodeIfPresent(category, forKey: .category)
    }
}
