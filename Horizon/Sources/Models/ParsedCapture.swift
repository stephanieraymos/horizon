import Foundation

/// Structured result of the `parse-capture` edge function — raw items the model
/// extracted, before they're resolved against people/dates/stores in the app.
struct ParsedCapture: Codable {
    var packing: [ParsedPacking] = []
    var todos: [ParsedTodo] = []
    var shopping: [ParsedShopping] = []

    init() {}

    // Tolerate a missing top-level array (e.g. if the model omits an empty list)
    // so one absent key doesn't fail the whole parse. Synthesized Decodable would
    // ignore the property defaults above and throw keyNotFound.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        packing = try c.decodeIfPresent([ParsedPacking].self, forKey: .packing) ?? []
        todos = try c.decodeIfPresent([ParsedTodo].self, forKey: .todos) ?? []
        shopping = try c.decodeIfPresent([ParsedShopping].self, forKey: .shopping) ?? []
    }
}

struct ParsedPacking: Codable {
    var item: String
    /// "me" (the speaker), "everyone", or a person's name.
    var person: String
}

struct ParsedTodo: Codable {
    var title: String
    var due: ParsedDue?
}

/// A relative due time the app turns into a concrete date using the trip dates.
struct ParsedDue: Codable {
    /// "departure" | "return" | "none"
    var anchor: String
    /// Days relative to the anchor (e.g. -1 = the night before departure).
    var offsetDays: Int
    /// An explicit calendar date "YYYY-MM-DD" if one was literally stated.
    var date: String?
}

struct ParsedShopping: Codable {
    var item: String
    var store: String?
    var quantity: String?
}
