import SwiftUI

/// Phase-0 shell. Real Trips / Someday / Notes screens land in later phases.
struct MainTabView: View {
    var body: some View {
        TabView {
            PlaceholderTab(
                title: "Trips",
                systemImage: "airplane",
                message: "Upcoming and past trips will live here."
            )
            .tabItem { Label("Trips", systemImage: "airplane") }

            PlaceholderTab(
                title: "Someday",
                systemImage: "map",
                message: "Bucket-list destinations and someday plans."
            )
            .tabItem { Label("Someday", systemImage: "map") }

            PlaceholderTab(
                title: "Notes",
                systemImage: "note.text",
                message: "Travel knowledge and trip notes."
            )
            .tabItem { Label("Notes", systemImage: "note.text") }

            SettingsTab()
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
    }
}

private struct PlaceholderTab: View {
    let title: String
    let systemImage: String
    let message: String

    var body: some View {
        NavigationStack {
            ContentUnavailableView {
                Label(title, systemImage: systemImage)
            } description: {
                Text(message)
            }
            .navigationTitle(title)
        }
    }
}

private struct SettingsTab: View {
    @Environment(AuthStore.self) private var authStore

    var body: some View {
        NavigationStack {
            Form {
                Section("Account") {
                    LabeledContent("Signed in as", value: authStore.userEmail ?? "—")
                    Button("Sign Out", role: .destructive) {
                        Task { await authStore.signOut() }
                    }
                }
                Section {
                    LabeledContent("App", value: "Horizon")
                    LabeledContent("Backend", value: "Shared family project")
                }
            }
            .navigationTitle("Settings")
        }
    }
}
