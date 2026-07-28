import SwiftUI
import Observation

/// Handles `horizon://trip/<uuid>` deep links (shared event/trip links). Setting
/// `pendingTripID` makes RootView present that trip, from any tab.
@Observable
@MainActor
final class DeepLinkRouter {
    var pendingTripID: UUID?

    func handle(_ url: URL) {
        guard url.scheme == "horizon", url.host == "trip",
              let last = url.pathComponents.last, let id = UUID(uuidString: last) else { return }
        pendingTripID = id
    }

    /// A shareable link to a plan/trip.
    static func link(forTrip id: UUID) -> URL? {
        URL(string: "horizon://trip/\(id.uuidString)")
    }
}

struct RootView: View {
    @Environment(AuthStore.self) private var authStore
    @Environment(FamilyStore.self) private var family
    @Environment(TripsStore.self) private var trips
    @Environment(TravelNotesStore.self) private var travelNotes
    @Environment(DeepLinkRouter.self) private var deepLink

    var body: some View {
        Group {
            if authStore.isSignedIn {
                MainTabView()
            } else {
                SignInView()
            }
        }
        .task(id: authStore.isSignedIn) {
            guard authStore.isSignedIn else { return }
            await family.load()
            await trips.load()
            await travelNotes.load()
        }
        .onOpenURL { deepLink.handle($0) }
        // Present a deep-linked trip from any tab once it's loaded.
        .sheet(item: Binding(
            get: { deepLink.pendingTripID.flatMap { id in trips.trips.first { $0.id == id } } },
            set: { if $0 == nil { deepLink.pendingTripID = nil } }
        )) { trip in
            NavigationStack { TripDetailView(trip: trip) }
        }
    }
}
