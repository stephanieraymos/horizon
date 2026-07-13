import SwiftUI

@main
struct HorizonApp: App {
    @State private var authStore = AuthStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .tint(Theme.Colors.brand)
                .environment(authStore)
        }
        #if targetEnvironment(macCatalyst)
        .defaultSize(width: 1100, height: 800)
        #endif
    }
}
