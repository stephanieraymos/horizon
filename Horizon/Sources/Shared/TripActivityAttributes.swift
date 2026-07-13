#if canImport(ActivityKit) && !targetEnvironment(macCatalyst)
import ActivityKit
import Foundation

/// Live Activity for a trip countdown. The app starts it; the widget extension
/// renders it on the Lock Screen and in the Dynamic Island. iPhone-only
/// (ActivityKit isn't available under Mac Catalyst).
struct TripActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        /// Departure moment — the widget shows a live countdown to it.
        var departDate: Date
        var returnDate: Date?
    }

    var tripName: String
    var destination: String?
}
#endif
