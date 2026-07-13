import Foundation

/// Foundation-only snapshot of the next trip, shared between the app and the
/// widget via an App Group. The app writes it (a widget extension can't hold a
/// Supabase session); the widget renders this cache.
struct TripWidgetSnapshot: Codable {
    var generatedAt: Date
    var tripName: String?
    var destination: String?
    var departDate: Date?
    var returnDate: Date?
    var isSomeday: Bool
    var upcomingCount: Int

    static let appGroup = "group.com.stephanieraymos.horizon"
    static let key = "next-trip"

    /// Whole days from today to departure (nil if no dated trip).
    var daysUntil: Int? {
        guard let departDate else { return nil }
        let cal = Calendar.current
        return cal.dateComponents([.day], from: cal.startOfDay(for: Date()),
                                  to: cal.startOfDay(for: departDate)).day
    }

    var countdownText: String {
        guard let days = daysUntil else { return "Someday" }
        if let end = returnDate, days <= 0, end >= Calendar.current.startOfDay(for: Date()) { return "Now" }
        if days < 0 { return "" }
        if days == 0 { return "Today" }
        if days == 1 { return "Tomorrow" }
        return "\(days) days"
    }

    static func load() -> TripWidgetSnapshot? {
        guard let data = UserDefaults(suiteName: appGroup)?.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(TripWidgetSnapshot.self, from: data)
    }

    static func save(_ snapshot: TripWidgetSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        UserDefaults(suiteName: appGroup)?.set(data, forKey: key)
    }

    static let empty = TripWidgetSnapshot(generatedAt: Date(), tripName: nil, destination: nil,
                                          departDate: nil, returnDate: nil, isSomeday: false, upcomingCount: 0)

    static let preview = TripWidgetSnapshot(
        generatedAt: Date(), tripName: "Camping Trip", destination: "Bodega Bay",
        departDate: Calendar.current.date(byAdding: .day, value: 8, to: Date()),
        returnDate: Calendar.current.date(byAdding: .day, value: 10, to: Date()),
        isSomeday: false, upcomingCount: 3)
}
