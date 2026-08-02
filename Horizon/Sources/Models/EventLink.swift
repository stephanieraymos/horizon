import Foundation

/// A link attached to a Horizon event/trip, stored in the shared `tm_links`
/// table with `type = ["event"]` so it stays out of Orbit/Canopy Links tabs
/// (those filter by type). `trip_id` scopes it to the event.
struct EventLink: Identifiable, Codable, Hashable {
    let id: UUID
    var tripID: UUID?
    var title: String
    var url: String
    var type: [String]

    enum CodingKeys: String, CodingKey {
        case id, title, url, type
        case tripID = "trip_id"
    }

    init(id: UUID = UUID(), tripID: UUID, title: String, url: String, type: [String] = ["event"]) {
        self.id = id; self.tripID = tripID; self.title = title; self.url = url; self.type = type
    }

    /// A cleaned https URL for opening (adds a scheme if the user typed a bare host).
    var openURL: URL? {
        let t = url.trimmingCharacters(in: .whitespaces)
        if let u = URL(string: t), u.scheme != nil { return u }
        return URL(string: "https://\(t)")
    }

    var displayTitle: String {
        let t = title.trimmingCharacters(in: .whitespaces)
        return t.isEmpty ? (openURL?.host ?? url) : t
    }
}
