import SwiftUI

struct RootView: View {
    @Environment(AuthStore.self) private var authStore
    @Environment(FamilyStore.self) private var family
    @Environment(TripsStore.self) private var trips
    @Environment(TravelNotesStore.self) private var travelNotes

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
    }
}
