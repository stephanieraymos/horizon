import Foundation

/// A shopping "store" (where to buy an item) — mirror of `fam_shopping_stores`.
/// Family-scoped; feeds the shopping "From" combobox, the store filter, and the
/// quick-capture parser's store matching.
struct ShoppingStore: Codable, Identifiable, Hashable {
    let id: UUID
    var familyID: UUID
    var name: String

    enum CodingKeys: String, CodingKey {
        case id
        case familyID = "family_id"
        case name
    }

    init(id: UUID = UUID(), familyID: UUID, name: String) {
        self.id = id; self.familyID = familyID; self.name = name
    }
}
