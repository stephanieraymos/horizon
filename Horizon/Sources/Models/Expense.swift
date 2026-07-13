import Foundation

/// Category is a free-form String in both apps (the enum is UI-only), so richer
/// values don't break Glade's decode.
enum ExpenseCategory: String, CaseIterable, Hashable {
    case flights = "Flights"
    case lodging = "Lodging"
    case food = "Food"
    case activities = "Activities"
    case transport = "Transport"
    case merch = "Merch"
    case other = "Other"

    var systemImage: String {
        switch self {
        case .flights: "airplane"; case .lodging: "bed.double"; case .food: "fork.knife"
        case .activities: "figure.hiking"; case .transport: "car"; case .merch: "bag"
        case .other: "tag"
        }
    }

    static func icon(for raw: String) -> String {
        ExpenseCategory(rawValue: raw)?.systemImage ?? "tag"
    }
}

/// Mirror of `fam_trip_expenses`. `amount` (dollars) + `loggedAt` stay as Glade
/// expects; `paidBy`/`spentOn`/`placeID` are additive Phase-3 columns.
struct Expense: Codable, Identifiable, Hashable {
    let id: UUID
    var tripID: UUID
    var category: String
    var description: String?
    var amount: Double
    var loggedBy: UUID?
    var paidBy: UUID?
    var spentOn: Date?
    var placeID: UUID?
    var loggedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case tripID = "trip_id"
        case category, description, amount
        case loggedBy = "logged_by"
        case paidBy = "paid_by"
        case spentOn = "spent_on"
        case placeID = "place_id"
        case loggedAt = "logged_at"
    }

    init(id: UUID = UUID(), tripID: UUID, category: String = ExpenseCategory.food.rawValue,
         description: String? = nil, amount: Double = 0, loggedBy: UUID? = nil,
         paidBy: UUID? = nil, spentOn: Date? = nil, placeID: UUID? = nil) {
        self.id = id; self.tripID = tripID; self.category = category
        self.description = description; self.amount = amount; self.loggedBy = loggedBy
        self.paidBy = paidBy; self.spentOn = spentOn; self.placeID = placeID
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        tripID = try c.decode(UUID.self, forKey: .tripID)
        category = try c.decode(String.self, forKey: .category)
        description = try c.decodeIfPresent(String.self, forKey: .description)
        amount = try c.decode(Double.self, forKey: .amount)
        loggedBy = try c.decodeIfPresent(UUID.self, forKey: .loggedBy)
        paidBy = try c.decodeIfPresent(UUID.self, forKey: .paidBy)
        spentOn = try decodeDateOnlyIfPresent(c, forKey: .spentOn)
        placeID = try c.decodeIfPresent(UUID.self, forKey: .placeID)
        loggedAt = try c.decodeIfPresent(Date.self, forKey: .loggedAt)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(tripID, forKey: .tripID)
        try c.encode(category, forKey: .category)
        try c.encodeIfPresent(description, forKey: .description)
        try c.encode(amount, forKey: .amount)
        try c.encodeIfPresent(loggedBy, forKey: .loggedBy)
        try c.encodeIfPresent(paidBy, forKey: .paidBy)
        if let spentOn { try encodeDateOnly(&c, spentOn, forKey: .spentOn) }
        try c.encodeIfPresent(placeID, forKey: .placeID)
    }
}

/// Mirror of `fam_expense_splits` — one member's share of an expense.
struct ExpenseSplit: Codable, Identifiable, Hashable {
    let id: UUID
    var expenseID: UUID
    var memberID: UUID
    var amount: Double

    enum CodingKeys: String, CodingKey {
        case id
        case expenseID = "expense_id"
        case memberID = "member_id"
        case amount
    }

    init(id: UUID = UUID(), expenseID: UUID, memberID: UUID, amount: Double) {
        self.id = id; self.expenseID = expenseID; self.memberID = memberID; self.amount = amount
    }
}
