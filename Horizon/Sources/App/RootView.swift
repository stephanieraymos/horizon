import SwiftUI
import Observation

/// Handles `horizon://trip/<uuid>` and `horizon://event/<uuid>` deep links
/// (shared trip / standalone-event links, e.g. from Solstice's Horizon overlay).
/// Setting `pendingTripID` / `pendingEventID` makes RootView present that item,
/// from any tab.
@Observable
@MainActor
final class DeepLinkRouter {
    var pendingTripID: UUID?
    var pendingEventID: UUID?

    func handle(_ url: URL) {
        guard url.scheme == "horizon",
              let last = url.pathComponents.last, let id = UUID(uuidString: last) else { return }
        switch url.host {
        case "trip":  pendingTripID = id
        case "event": pendingEventID = id
        default:      break
        }
    }

    /// A shareable link to a plan/trip.
    static func link(forTrip id: UUID) -> URL? {
        URL(string: "horizon://trip/\(id.uuidString)")
    }

    /// A shareable link to a standalone event / key date / birthday countdown.
    static func link(forEvent id: UUID) -> URL? {
        URL(string: "horizon://event/\(id.uuidString)")
    }
}

struct RootView: View {
    @Environment(AuthStore.self) private var authStore
    @Environment(FamilyStore.self) private var family
    @Environment(TripsStore.self) private var trips
    @Environment(TravelNotesStore.self) private var travelNotes
    @Environment(EventsStore.self) private var events
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
            await events.load()
        }
        .onOpenURL { deepLink.handle($0) }
        // Present a deep-linked trip from any tab once it's loaded.
        .sheet(item: Binding(
            get: { deepLink.pendingTripID.flatMap { id in trips.trips.first { $0.id == id } } },
            set: { if $0 == nil { deepLink.pendingTripID = nil } }
        )) { trip in
            NavigationStack { TripDetailView(trip: trip) }
        }
        // Present a deep-linked standalone event (opens its editor/detail).
        .sheet(item: Binding(
            get: { deepLink.pendingEventID.flatMap { id in events.events.first { $0.id == id } } },
            set: { if $0 == nil { deepLink.pendingEventID = nil } }
        )) { event in
            EventEditView(existing: event)
        }
    }
}
