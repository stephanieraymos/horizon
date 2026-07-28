import SwiftUI
import AppShellKit

/// Horizon's tabs. First `maxPrimary` show in the bar, the rest in "More"; order
/// is user-customizable and synced (AppShellKit + app_tab_prefs). AppShell owns
/// each tab's NavigationStack, so every root view below is bare (no NavigationStack
/// of its own) — that's what avoids the nested-stack "pushes behind" bug.
enum HorizonTab: String, CaseIterable, ShellTab {
    // Events is the unified trips + countdowns board (replaces separate tabs).
    case home, events, dates, someday, people

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home:    "Home"
        case .events:  "Events"
        case .dates:   "Dates"
        case .someday: "Someday"
        case .people:  "People"
        }
    }

    var systemImage: String {
        switch self {
        case .home:    "house"
        case .events:  "calendar"
        case .dates:   "heart"
        case .someday: "map"
        case .people:  "person.2"
        }
    }
}

struct MainTabView: View {
    @State private var prefs = ShellPrefsStore(client: supabase, appKey: "horizon")

    var body: some View {
        AppShell(tabs: HorizonTab.allCases, maxPrimary: 4, prefs: prefs) { tab in
            root(for: tab)
        }
    }

    @ViewBuilder
    private func root(for tab: HorizonTab) -> some View {
        switch tab {
        case .home:    HomeView()
        case .events:  EventsBoardView()
        case .dates:   DatesView()
        case .someday: SomedayView()
        case .people:  PeopleView()
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
                Section("People") {
                    NavigationLink {
                        PeopleView()
                    } label: {
                        Label("Manage People", systemImage: "person.2.fill")
                    }
                    Button {
                        showTravelers = true
                    } label: {
                        Label("Travelers & Documents", systemImage: "person.text.rectangle")
                    }
                }
                Section("Trip planning") {
                    Button {
                        showTemplates = true
                    } label: {
                        Label("Packing Templates", systemImage: "suitcase.fill")
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
