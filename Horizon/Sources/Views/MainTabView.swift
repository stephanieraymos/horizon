import SwiftUI

struct MainTabView: View {
    // Keep to 5 tabs: a 6th+ makes iOS collapse the extras into a "More" tab that
    // wraps them in its own navigation controller, nesting each tab's own
    // NavigationStack — the source of the double back button / stray back arrow /
    // misplaced toolbar. Notes + Settings are reached from Home instead.
    var body: some View {
        TabView {
            HomeView()
                .tabItem { Label("Home", systemImage: "house") }

            EventsBoardView()
                .tabItem { Label("Events", systemImage: "calendar") }

            SomedayView()
                .tabItem { Label("Someday", systemImage: "map") }

            DatesView()
                .tabItem { Label("Dates", systemImage: "heart") }
        }
    }
}

struct PlaceholderTab: View {
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

/// Settings — presented as a sheet from Home (no longer a tab).
struct SettingsView: View {
    @Environment(AuthStore.self) private var authStore
    @Environment(FamilyStore.self) private var family
    @Environment(\.dismiss) private var dismiss
    @State private var showTemplates = false
    @State private var showTravelers = false
    @AppStorage("notifications.enabled") private var notificationsEnabled = true

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Trip reminders", isOn: $notificationsEnabled)
                } header: {
                    Text("Notifications")
                } footer: {
                    Text("Reminders to start packing, plus the night before a reservation and a heads-up before a date.")
                }
                Section("Trip planning") {
                    Button {
                        showTemplates = true
                    } label: {
                        Label("Packing Templates", systemImage: "suitcase.fill")
                    }
                    Button {
                        showTravelers = true
                    } label: {
                        Label("Travelers & Documents", systemImage: "person.text.rectangle")
                    }
                }
                Section("Account") {
                    LabeledContent("Signed in as", value: authStore.userEmail ?? "—")
                    if let member = family.currentMember {
                        LabeledContent("Member", value: member.name)
                    }
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
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .onChange(of: notificationsEnabled) { _, enabled in
                if !enabled {
                    Task { await NotificationManager.sync(trips: [], reservations: [], dates: [], enabled: false) }
                }
            }
            .sheet(isPresented: $showTemplates) { PackingTemplatesView() }
            .sheet(isPresented: $showTravelers) { TravelerProfilesView() }
        }
    }
}
