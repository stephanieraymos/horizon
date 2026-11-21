import SwiftUI
import AppShellKit

/// Horizon's tabs. First `maxPrimary` show in the bar, the rest in "More"; order
/// is user-customizable and synced (AppShellKit + app_tab_prefs). AppShell owns
/// each tab's NavigationStack, so every root view below is bare (no NavigationStack
/// of its own) — that's what avoids the nested-stack "pushes behind" bug.
enum HorizonTab: String, CaseIterable, ShellTab {
    // Events is the unified trips + countdowns board (replaces separate tabs).
    case home, countdowns, events, dates, someday, people

    var id: String { rawValue }

    /// Events owns its own navigation container: on regular×regular (iPad,
    /// Split View, the Duo's inner display) it's a NavigationSplitView — trip
    /// list beside trip detail — instead of AppShell's default single-column
    /// NavigationStack push. See `EventsBoardView`.
    var ownsNavigation: Bool { self == .events }

    var title: String {
        switch self {
        case .home:       "Home"
        case .countdowns: "Countdowns"
        // Trips, parties, dinners — the things you plan. "Events" beside a
        // Countdowns tab would read as the same idea twice.
        case .events:     "Plans"
        case .dates:   "Dates"
        case .someday: "Someday"
        case .people:  "People"
        }
    }

    var systemImage: String {
        switch self {
        case .home:       "house"
        case .countdowns: "hourglass"
        case .events:     "calendar"
        case .dates:   "heart"
        case .someday: "map"
        case .people:  "person.2"
        }
    }
}

/// A saved tab order predates Countdowns, and AppShell appends a tab a saved
/// order doesn't know about at the END — past the 4-tab bar, into More, which for
/// her is the same as not having it. So an order that has never seen
/// "countdowns" gets it right after Home. Read-side only: once she saves an order
/// that includes it (anywhere, More included) this leaves it exactly there.
enum HorizonTabOrder {
    nonisolated static func normalize(_ ids: [String]) -> [String] {
        let known = Set(HorizonTab.allCases.map(\.rawValue))
        var out: [String] = []
        for id in ids where known.contains(id) && !out.contains(id) { out.append(id) }
        guard !out.isEmpty else { return out }
        let countdowns = HorizonTab.countdowns.rawValue
        if !out.contains(countdowns) {
            let afterHome = out.firstIndex(of: HorizonTab.home.rawValue).map { $0 + 1 } ?? 0
            out.insert(countdowns, at: min(afterHome, out.count))
        }
        return out
    }
}

struct MainTabView: View {
    @Environment(\.horizontalSizeClass) private var hSizeClass
    @Environment(\.verticalSizeClass) private var vSizeClass
    @State private var prefs = ShellPrefsStore(client: supabase, appKey: "horizon",
                                               normalizeOrder: HorizonTabOrder.normalize)
    /// The selected tab, owned here so it survives a shell swap (fold/unfold, Split
    /// View resize): both shells read and write it.
    @State private var selectedTab: String = HorizonTab.home.rawValue
    /// Settings is a sidebar-only row; it sits beside, not inside, `selectedTab`
    /// so the tab bar never receives an id it does not know.
    @State private var showsSettings = false

    /// Any window that is regular in BOTH directions gets the sidebar shell (iPad,
    /// Mac, and the iPhone Duo's inner display, which is a PHONE idiom at
    /// regular x regular). Everything else is the AppShellKit tab bar. Size classes
    /// only, never idiom or UIScreen: AppShellKit forces the phone tab bar for any
    /// phone-idiom device (a Duo `UITabBarItem` crash workaround), so a wide phone
    /// would otherwise get one stretched column. The sidebar shell is a
    /// `NavigationSplitView`, not a `TabView`, so it avoids those crashes; the fold
    /// itself is UNVERIFIED (needs a real Duo). Mirrors Canopy's `usesSidebar`.
    private var usesSidebar: Bool {
        hSizeClass == .regular && vSizeClass == .regular
    }

    private var tabSelection: Binding<String> {
        Binding(get: { selectedTab },
                set: {
                    guard HorizonTab(rawValue: $0) != nil else { return }
                    selectedTab = $0
                    showsSettings = false
                })
    }

    var body: some View {
        Group {
            if usesSidebar {
                HorizonSidebarShell(selectedTab: tabSelection, showsSettings: $showsSettings)
            } else {
                AppShell(tabs: HorizonTab.allCases, maxPrimary: 4, prefs: prefs,
                         selection: tabSelection) { tab in
                    HorizonTabRoot(tab: tab)
                }
            }
        }
        // Settings is a sidebar-only row; unfolding back to the tab bar must not
        // leave it selected for the next time the sidebar shell appears.
        .onChange(of: usesSidebar) { _, now in
            if !now { showsSettings = false }
        }
    }
}

/// One tab's root view, shared by the tab bar and the sidebar shell.
struct HorizonTabRoot: View {
    let tab: HorizonTab

    var body: some View {
        switch tab {
        case .home:       HomeView()
        case .countdowns: CountdownsView()
        case .events:     EventsBoardView()
        case .dates:      DatesView()
        case .someday:    SomedayView()
        case .people:     PeopleView()
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
    /// True when shown as the sidebar shell's detail rather than a sheet: there is
    /// nothing to dismiss, so no Done button.
    var embedded = false
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
                    Toggle("Reminders", isOn: $notificationsEnabled)
                } header: {
                    Text("Notifications")
                } footer: {
                    Text("Reminders to start packing, the night before a reservation, a heads-up before a date, and the morning of each countdown — plus a week’s notice for birthdays and anniversaries.")
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
                if !embedded {
                    ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
                }
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
