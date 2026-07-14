import Foundation

/// A loyalty/rewards membership (airline, hotel, rental).
struct LoyaltyProgram: Codable, Identifiable, Hashable {
    var id: UUID
    var program: String
    var number: String

    init(id: UUID = UUID(), program: String, number: String) {
        self.id = id; self.program = program; self.number = number
    }
}

/// Reusable travel documents for one family member. Mirror of
/// `fam_traveler_profiles`. Passport number is sensitive — stored only in the
/// family's private, RLS-scoped backend.
struct TravelerProfile: Codable, Identifiable, Hashable {
    let id: UUID
    var familyID: UUID
    var memberID: UUID
    var passportNumber: String?
    var passportExpiry: Date?
    var knownTravelerNumber: String?
    var loyaltyPrograms: [LoyaltyProgram]
    var notes: String?

    enum CodingKeys: String, CodingKey {
        case id
        case familyID = "family_id"
        case memberID = "member_id"
        case passportNumber = "passport_number"
        case passportExpiry = "passport_expiry"
        case knownTravelerNumber = "known_traveler_number"
        case loyaltyPrograms = "loyalty_programs"
        case notes
    }

    init(id: UUID = UUID(), familyID: UUID, memberID: UUID, passportNumber: String? = nil,
         passportExpiry: Date? = nil, knownTravelerNumber: String? = nil,
         loyaltyPrograms: [LoyaltyProgram] = [], notes: String? = nil) {
        self.id = id; self.familyID = familyID; self.memberID = memberID
        self.passportNumber = passportNumber; self.passportExpiry = passportExpiry
        self.knownTravelerNumber = knownTravelerNumber; self.loyaltyPrograms = loyaltyPrograms
        self.notes = notes
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        familyID = try c.decode(UUID.self, forKey: .familyID)
        memberID = try c.decode(UUID.self, forKey: .memberID)
        passportNumber = try c.decodeIfPresent(String.self, forKey: .passportNumber)
        passportExpiry = try decodeDateOnlyIfPresent(c, forKey: .passportExpiry)
        knownTravelerNumber = try c.decodeIfPresent(String.self, forKey: .knownTravelerNumber)
        loyaltyPrograms = try c.decodeIfPresent([LoyaltyProgram].self, forKey: .loyaltyPrograms) ?? []
        notes = try c.decodeIfPresent(String.self, forKey: .notes)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(familyID, forKey: .familyID)
        try c.encode(memberID, forKey: .memberID)
        try c.encodeIfPresent(passportNumber, forKey: .passportNumber)
        if let passportExpiry { try encodeDateOnly(&c, passportExpiry, forKey: .passportExpiry) }
        try c.encodeIfPresent(knownTravelerNumber, forKey: .knownTravelerNumber)
        try c.encode(loyaltyPrograms, forKey: .loyaltyPrograms)
        try c.encodeIfPresent(notes, forKey: .notes)
    }

    /// Months of passport validity remaining relative to a trip's departure.
    /// Returns nil if no expiry recorded.
    func passportValidityWarning(forDeparture departure: Date?) -> PassportWarning? {
        guard let expiry = passportExpiry else { return nil }
        let ref = departure ?? Date()
        if expiry < ref { return .expired }
        // Many countries require 6 months' validity beyond entry.
        if let sixMonths = Calendar.current.date(byAdding: .month, value: 6, to: ref),
           expiry < sixMonths { return .expiringSoon }
        return nil
    }
}

enum PassportWarning {
    case expired
    case expiringSoon
}
