import SwiftUI

struct MainTabView: View {
    var body: some View {
        TabView {
            HomeView()
                .tabItem { Label("Home", systemImage: "house") }

            TripsListView()
                .tabItem { Label("Trips", systemImage: "airplane") }

            SomedayView()
                .tabItem { Label("Someday", systemImage: "map") }

            DatesView()
                .tabItem { Label("Dates", systemImage: "heart") }

            EventsListView()
                .tabItem { Label("Countdown", systemImage: "calendar.badge.clock") }

            NotesTabView()
                .tabItem { Label("Notes", systemImage: "note.text") }

            SettingsTab()
                .tabItem { Label("Settings", systemImage: "gearshape") }
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

private struct SettingsTab: View {
    @Environment(AuthStore.self) private var authStore
    @Environment(FamilyStore.self) private var family
    @State private var showTemplates = false
    @State private var showTravelers = false

    var body: some View {
        NavigationStack {
            Form {
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
            .sheet(isPresented: $showTemplates) { PackingTemplatesView() }
            .sheet(isPresented: $showTravelers) { TravelerProfilesView() }
        }
    }
}
