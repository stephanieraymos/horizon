import Foundation

enum FamilyRole: String, Codable, Hashable {
    case admin
    case child
    case none
}

/// Slim mirror of `fam_family_members` — enough to show travelers and scope
/// inserts by family. (Shoutout / household fields are omitted; unknown columns
/// in the row are simply ignored on decode.)
struct FamilyMember: Codable, Identifiable, Hashable {
    let id: UUID
    let familyID: UUID
    var userID: UUID?
    var name: String
    var role: FamilyRole
    var avatarURL: String?
    var birthday: Date?
    /// The person's bucket: household | extended | friend | coworker | provider |
    /// tester | … (freeform, editable in People management).
    var householdType: String?
    let createdAt: Date

    var isAdmin: Bool { role == .admin }
    /// A friendlier label for the bucket.
    var bucketLabel: String { (householdType ?? "household").capitalized }

    enum CodingKeys: String, CodingKey {
        case id
        case familyID = "family_id"
        case userID = "user_id"
        case name, role
        case avatarURL = "avatar_url"
        case birthday
        case householdType = "household_type"
        case createdAt = "created_at"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id       = try c.decode(UUID.self, forKey: .id)
        familyID = try c.decode(UUID.self, forKey: .familyID)
        userID   = try c.decodeIfPresent(UUID.self, forKey: .userID)
        name     = try c.decode(String.self, forKey: .name)
        role     = (try? c.decode(FamilyRole.self, forKey: .role)) ?? .none
        avatarURL = try c.decodeIfPresent(String.self, forKey: .avatarURL)
        birthday  = try decodeDateOnlyIfPresent(c, forKey: .birthday)
        householdType = try c.decodeIfPresent(String.self, forKey: .householdType)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
    }
}

/// A directional person↔person relationship (people_relationships): `label`
/// describes `fromPerson`'s relation to `toPerson` ("mom", "friend", …).
struct PersonRelationship: Codable, Identifiable, Hashable {
    let id: UUID
    var familyID: UUID
    var fromPerson: UUID
    var toPerson: UUID
    var label: String

    enum CodingKeys: String, CodingKey {
        case id, label
        case familyID = "family_id"
        case fromPerson = "from_person"
        case toPerson = "to_person"
    }
}
