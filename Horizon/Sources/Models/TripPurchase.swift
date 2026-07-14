import Foundation

enum PurchaseStatus: String, Codable, CaseIterable, Hashable {
    case notPurchased = "not_purchased"
    case inCart = "in_cart"
    case purchased

    var label: String {
        switch self {
        case .notPurchased: "To buy"; case .inCart: "In cart"; case .purchased: "Purchased"
        }
    }
    var systemImage: String {
        switch self {
        case .notPurchased: "circle"; case .inCart: "cart"; case .purchased: "checkmark.circle.fill"
        }
    }
    /// Tap cycles to the next state.
    var next: PurchaseStatus {
        switch self {
        case .notPurchased: .inCart; case .inCart: .purchased; case .purchased: .notPurchased
        }
    }
}

/// Mirror of `fam_trip_purchases` — a trip shopping-list item.
struct TripPurchase: Codable, Identifiable, Hashable {
    let id: UUID
    var familyID: UUID
    var tripID: UUID?
    var name: String
    var amountCents: Int?
    var purchaseDate: Date?
    var status: PurchaseStatus
    var tag: String?
    var purchasedFrom: String?
    var link: String?
    var notes: String?

    var amountDollars: Double? { amountCents.map { Double($0) / 100 } }
    var linkURL: URL? { link?.nilIfBlank.flatMap(URL.init) }

    enum CodingKeys: String, CodingKey {
        case id
        case familyID = "family_id"
        case tripID = "trip_id"
        case name
        case amountCents = "amount_cents"
        case purchaseDate = "purchase_date"
        case status, tag
        case purchasedFrom = "purchased_from"
        case link, notes
    }

    init(id: UUID = UUID(), familyID: UUID, tripID: UUID?, name: String = "",
         amountCents: Int? = nil, purchaseDate: Date? = nil, status: PurchaseStatus = .notPurchased,
         tag: String? = nil, purchasedFrom: String? = nil, link: String? = nil) {
        self.id = id; self.familyID = familyID; self.tripID = tripID; self.name = name
        self.amountCents = amountCents; self.purchaseDate = purchaseDate; self.status = status
        self.tag = tag; self.purchasedFrom = purchasedFrom; self.link = link
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        familyID = try c.decode(UUID.self, forKey: .familyID)
        tripID = try c.decodeIfPresent(UUID.self, forKey: .tripID)
        name = try c.decode(String.self, forKey: .name)
        amountCents = try c.decodeIfPresent(Int.self, forKey: .amountCents)
        purchaseDate = try decodeDateOnlyIfPresent(c, forKey: .purchaseDate)
        status = (try? c.decode(PurchaseStatus.self, forKey: .status)) ?? .notPurchased
        tag = try c.decodeIfPresent(String.self, forKey: .tag)
        purchasedFrom = try c.decodeIfPresent(String.self, forKey: .purchasedFrom)
        link = try c.decodeIfPresent(String.self, forKey: .link)
        notes = try c.decodeIfPresent(String.self, forKey: .notes)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(familyID, forKey: .familyID)
        try c.encodeIfPresent(tripID, forKey: .tripID)
        try c.encode(name, forKey: .name)
        try c.encodeIfPresent(amountCents, forKey: .amountCents)
        if let purchaseDate { try encodeDateOnly(&c, purchaseDate, forKey: .purchaseDate) }
        try c.encode(status, forKey: .status)
        try c.encodeIfPresent(tag, forKey: .tag)
        try c.encodeIfPresent(purchasedFrom, forKey: .purchasedFrom)
        try c.encodeIfPresent(link, forKey: .link)
        try c.encodeIfPresent(notes, forKey: .notes)
    }
}
