import SwiftUI

struct RootView: View {
    @Environment(AuthStore.self) private var authStore

    var body: some View {
        Group {
            if authStore.isSignedIn {
                MainTabView()
            } else {
                SignInView()
            }
        }
    }
}
