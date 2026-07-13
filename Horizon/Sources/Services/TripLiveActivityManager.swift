import Foundation
#if canImport(ActivityKit) && !targetEnvironment(macCatalyst)
import ActivityKit
#endif

/// Starts/stops the trip-countdown Live Activity. iPhone-only — ActivityKit is
/// unavailable under Mac Catalyst, so the whole thing is a no-op there.
enum TripLiveActivityManager {
    #if canImport(ActivityKit) && !targetEnvironment(macCatalyst)
    static var isSupported: Bool {
        ActivityAuthorizationInfo().areActivitiesEnabled
    }

    static func isRunning(tripName: String) -> Bool {
        Activity<TripActivityAttributes>.activities.contains { $0.attributes.tripName == tripName }
    }

    static func start(trip: Trip) {
        guard let depart = trip.departDate, isSupported else { return }
        let attrs = TripActivityAttributes(tripName: trip.name, destination: trip.destination)
        let state = TripActivityAttributes.ContentState(departDate: depart, returnDate: trip.returnDate)
        _ = try? Activity.request(attributes: attrs,
                                  content: .init(state: state, staleDate: nil))
    }

    static func stop(tripName: String) {
        Task {
            for activity in Activity<TripActivityAttributes>.activities
            where activity.attributes.tripName == tripName {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }
    }
    #else
    static var isSupported: Bool { false }
    static func isRunning(tripName: String) -> Bool { false }
    static func start(trip: Trip) {}
    static func stop(tripName: String) {}
    #endif
}
