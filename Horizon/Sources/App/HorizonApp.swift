import SwiftUI

@main
struct HorizonApp: App {
    @State private var authStore = AuthStore()
    @State private var family = FamilyStore()
    @State private var trips = TripsStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .tint(Theme.Colors.brand)
                .environment(authStore)
                .environment(family)
                .environment(trips)
        }
        #if targetEnvironment(macCatalyst)
        .defaultSize(width: 1100, height: 800)
        #endif
    }
}
