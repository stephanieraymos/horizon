import Foundation

/// Structured result of the `parse-capture` edge function — raw items the model
/// extracted, before they're resolved against people/dates/stores in the app.
struct ParsedCapture: Codable {
    var packing: [ParsedPacking] = []
    var todos: [ParsedTodo] = []
    var shopping: [ParsedShopping] = []
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
