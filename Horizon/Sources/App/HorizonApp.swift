import SwiftUI

@main
struct HorizonApp: App {
    @State private var authStore = AuthStore()
    @State private var family = FamilyStore()
    @State private var trips = TripsStore()
    @State private var travelNotes = TravelNotesStore()
    @State private var dates = DateNightsStore()
    @State private var events = EventsStore()
    @State private var packingTemplates = PackingTemplatesStore()
    @State private var travelerProfiles = TravelerProfilesStore()
    @State private var dashboard = DashboardStore()

    init() {
        // Give the shared image disk cache real capacity so photos are fetched
        // once and never re-egress on re-render/scroll (the egress-runaway fix).
        HorizonImageLoader.configureSharedCache()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .tint(Theme.Colors.brand)
                .environment(authStore)
                .environment(family)
                .environment(trips)
                .environment(travelNotes)
                .environment(dates)
                .environment(events)
                .environment(packingTemplates)
                .environment(travelerProfiles)
                .environment(dashboard)
        }
        #if targetEnvironment(macCatalyst)
        .defaultSize(width: 1100, height: 800)
        #endif
    }
}
