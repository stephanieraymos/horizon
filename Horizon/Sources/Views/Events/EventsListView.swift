import SwiftUI
import DuoKit

/// The Plans board — trips, and the parties, dinners, gatherings and
/// celebrations planned the same way — with an All / Trips / Events filter.
///
/// Countdowns used to live here too, under an All/Trips/Countdowns picker, and
/// every dated trip showed twice (once as itself, once as the `fam_events` copy
/// `EventsStore.syncCountdown` writes for it). They moved to `CountdownsView`,
/// which merges plans and countdowns without the copy; this board is only the
/// things you plan.
///
/// Owns its own navigation (`HorizonTab.ownsNavigation`) so it can be a real
/// NavigationSplitView on regular×regular — plan list beside plan detail —
/// rather than AppShell's default single-column push, which on a wide screen
/// would just replace the list with the detail in place (an iPhone push, wider).
struct EventsBoardView: View {
    @Environment(TripsStore.self) private var trips
    @Environment(EventsStore.self) private var events
    @Environment(FamilyStore.self) private var family
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    @State private var search = ""
    @State private var typeFilter: TypeFilter = .all
    @State private var statusFilter: TripStatus?
    @State private var showArchived = false
    @State private var openTrip: Trip?

    // One `newKind` sheet covers every plan kind (including Trip) — a second
    // isPresented sheet for the Trip case was a duplicate presentation where
    // stacked .sheet modifiers can shadow each other and leave a menu item
    // opening nothing.
    @State private var newKind: PlanKind?
    @State private var manageSheet: ManageSheet?

    private enum ManageSheet: Int, Identifiable { case destinations, places; var id: Int { rawValue } }

    /// Trips travel; Events are everything else you plan (party, dinner…).
    private enum TypeFilter: String, CaseIterable, Identifiable {
        case all = "All", trips = "Trips", events = "Events"
        var id: String { rawValue }
    }

    /// iPad/Split-View/the Duo's inner display — same check AppShellKit uses to
    /// decide sidebar vs. tab bar. Reused here for the inner list↔detail split.
    private var isRegularWidth: Bool {
        DuoDisplay.isInnerDisplay(horizontal: horizontalSizeClass, vertical: verticalSizeClass)
    }

    // MARK: - Matching (kind + search + status)

    private func tripMatches(_ t: Trip) -> Bool {
        let kindOK: Bool
        switch typeFilter {
        case .all:    kindOK = true
        case .trips:  kindOK = t.kind.isTravel
        case .events: kindOK = !t.kind.isTravel
        }
        let s = search.trimmingCharacters(in: .whitespaces).lowercased()
        let textOK = s.isEmpty
            || t.name.lowercased().contains(s)
            || (t.destination?.lowercased().contains(s) ?? false)
            || t.kind.label.lowercased().contains(s)
            || (t.departDate.map { Trip.yearFormatter.string(from: $0).contains(s) } ?? false)
        let statusOK = statusFilter == nil || t.status == statusFilter
        return kindOK && textOK && statusOK
    }

    private var upcomingPlans: [Trip] { trips.upcoming.filter(tripMatches) }
    private var pastPlans: [Trip] { trips.past.filter(tripMatches) }
    private var archivedPlans: [Trip] { trips.archivedTrips.filter(tripMatches) }

    /// The status menu's words. Status is one stored value per plan, shown as
    /// "Booked / In progress" for a trip and "Confirmed / Happening" for an
    /// event; with both kinds on screen, the travel words (most of her plans).
    private var statusWordsKind: PlanKind { typeFilter == .events ? .party : .trip }

    // MARK: - Actions

    private func archive(_ trip: Trip) async {
        await events.deleteForTrip(trip.id, keepingLinks: true)
        await trips.setArchived(trip, true)
    }
    private func restore(_ trip: Trip) async {
        await trips.setArchived(trip, false)
        await events.syncCountdown(forTripID: trip.id, familyID: trip.familyID,
                                   name: trip.name, departDate: trip.departDate,
                                   createdBy: family.currentMember?.userID)
    }

    // MARK: - Body

    // This tab owns its own navigation container (HorizonTab.ownsNavigation),
    // so AppShell never wraps it: regular×regular gets a real NavigationSplitView
    // (list beside detail); everything narrower keeps the familiar push. Both
    // shapes share `openTrip` as the "current plan" — a push destination in the
    // stack, a selection in the split view.
    var body: some View {
        Group {
            if isRegularWidth {
                NavigationSplitView {
                    contentColumn
                } detail: {
                    if let trip = openTrip {
                        // TripDetailView owns a whole TripDetailStore plus edit/
                        // reservation/cover-photo state seeded from `trip` at
                        // init — without `.id()` switching plans in the list
                        // would leave the previous plan's entire detail (and
                        // its in-flight edits) on screen under the new one's
                        // selected row.
                        //
                        // Its own NavigationStack so the plan's pushes (Notes,
                        // packing, purchases) push inside the detail column, and
                        // the `.id` is on the STACK so choosing another plan also
                        // drops anything pushed for the previous one.
                        NavigationStack {
                            TripDetailView(trip: trip)
                        }
                        .id(trip.id)
                    } else {
                        ContentUnavailableView(
                            "Select a plan",
                            systemImage: "calendar",
                            description: Text("Pick a trip or event from the list to see its details here."))
                    }
                }
                .navigationSplitViewStyle(.balanced)
            } else {
                NavigationStack {
                    contentColumn
                        .navigationDestination(item: $openTrip) { TripDetailView(trip: $0) }
                }
            }
        }
        .sheet(item: $newKind) { k in
            if let familyID = family.familyID {
                TripEditView(trip: Trip(familyID: familyID, name: "", kind: k))
            } else {
                Text("Loading your family…").padding()
            }
        }
        .sheet(item: $manageSheet) { s in
            NavigationStack {
                switch s {
                case .destinations: DestinationsView()
                case .places: PlacesView()
                }
            }
        }
    }

    /// The list column — filter picker and the Upcoming/Past/Not-going sections.
    /// A NavigationStack root on iPhone; the sidebar column of a
    /// NavigationSplitView on regular width.
    private var contentColumn: some View {
        content
            .navigationTitle("Plans")
            .searchable(text: $search, prompt: "Search plans")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Button("Destinations", systemImage: "mappin.and.ellipse") { manageSheet = .destinations }
                        Button("Places", systemImage: "map") { manageSheet = .places }
                    } label: { Label("Destinations & Places", systemImage: "map") }
                }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button { statusFilter = nil } label: {
                            Label("All statuses", systemImage: statusFilter == nil ? "checkmark" : "line.3.horizontal")
                        }
                        ForEach(TripStatus.allCases, id: \.self) { s in
                            Button { statusFilter = s } label: {
                                Label(s.label(for: statusWordsKind),
                                      systemImage: statusFilter == s ? "checkmark" : s.systemImage(for: statusWordsKind))
                            }
                        }
                    } label: {
                        Label("Filter by status",
                              systemImage: statusFilter == nil ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        ForEach(PlanKind.allCases) { k in
                            Button { newKind = k } label: { Label("New \(k.label)", systemImage: k.systemImage) }
                        }
                    } label: { Label("Add", systemImage: "plus") }
                }
            }
            .task {
                if trips.trips.isEmpty { await trips.load() }
                if family.members.isEmpty { await family.load() }
            }
    }

    @ViewBuilder
    private var content: some View {
        if trips.isLoading && trips.trips.isEmpty {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if trips.trips.isEmpty {
            ContentUnavailableView {
                Label("Nothing planned yet", systemImage: "calendar")
            } description: {
                Text("Plan a trip, a party, a dinner — anything with a date and a place.")
            } actions: {
                Button("New Trip") { newKind = .trip }
                    .buttonStyle(.borderedProminent)
                Button("New Party") { newKind = .party }
            }
        } else {
            // Always keep the board (and its filter Picker) mounted when any data
            // exists; the "nothing matches this filter" message lives INSIDE the
            // board so the user never loses the controls to change the filter.
            board
        }
    }

    private var board: some View {
        VStack(spacing: 0) {
            Picker("Filter", selection: $typeFilter) {
                ForEach(TypeFilter.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.vertical, 8)

            if upcomingPlans.isEmpty && pastPlans.isEmpty && archivedPlans.isEmpty {
                filteredEmpty
            } else {
                List {
                    if !upcomingPlans.isEmpty {
                        Section("Upcoming") {
                            ForEach(upcomingPlans) { tripRow($0) }
                        }
                    }
                    if !pastPlans.isEmpty {
                        Section("Past") {
                            ForEach(pastPlans) { tripRow($0) }
                        }
                    }
                    if !archivedPlans.isEmpty {
                        Section {
                            if showArchived {
                                ForEach(archivedPlans) { tripRow($0) }
                            }
                        } header: {
                            Button {
                                withAnimation { showArchived.toggle() }
                            } label: {
                                HStack {
                                    Text("Not going (\(archivedPlans.count))")
                                    Spacer()
                                    Image(systemName: showArchived ? "chevron.down" : "chevron.right")
                                        .font(.caption)
                                }
                            }
                            .foregroundStyle(.secondary)
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .refreshable { await trips.load() }
            }
        }
    }

    /// Shown inside `board` (Picker still above) when the current filter/search
    /// matches nothing but plans exist elsewhere.
    @ViewBuilder
    private var filteredEmpty: some View {
        if !search.isEmpty {
            ContentUnavailableView.search
        } else {
            ContentUnavailableView(
                "Nothing here",
                systemImage: "line.3.horizontal.decrease.circle",
                description: Text(filteredEmptyHint))
        }
    }

    private var filteredEmptyHint: String {
        switch typeFilter {
        case .trips:  return "No trips match. Try another filter above."
        case .events: return "No events match. Try another filter above."
        case .all:    return "Nothing matches the current filters."
        }
    }

    // MARK: - Rows

    // A plain Button + `openTrip` (rather than value-based NavigationLink) so the
    // same tap works whether it's pushing a stack destination (compact) or just
    // swapping the split view's detail column (regular) — see `body`.
    private func tripRow(_ trip: Trip) -> some View {
        Button {
            openTrip = trip
        } label: {
            HStack(spacing: 6) {
                TripRowLabel(trip: trip)
                // A plain Button drops the disclosure chevron NavigationLink used
                // to draw for free — restore it in push mode only; the split
                // view's detail column IS the disclosure, so a chevron there
                // would be a chevron to nowhere.
                if !isRegularWidth {
                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(isRegularWidth && openTrip?.id == trip.id
                            ? Theme.Colors.brand.opacity(0.12) : Color.clear)
        .swipeActions(edge: .trailing) {
            if trip.archived {
                Button { Task { await restore(trip) } } label: {
                    Label("Restore", systemImage: "arrow.uturn.backward")
                }.tint(Theme.Colors.brand)
            } else {
                Button { Task { await archive(trip) } } label: {
                    Label("Not going", systemImage: "xmark.bin")
                }.tint(.orange)
            }
        }
    }
}
