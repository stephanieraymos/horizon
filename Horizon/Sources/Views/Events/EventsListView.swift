import SwiftUI

/// The unified "Events" board — trips and one-day countdowns in one place, with a
/// simple All / Trips / Events filter. Replaces the old separate "Trips" and
/// "Countdown" tabs. Member birthdays are synthesized in-memory from
/// `fam_family_members.birthday` (never persisted); trips and events are sorted
/// together by how soon they are.
struct EventsBoardView: View {
    @Environment(TripsStore.self) private var trips
    @Environment(EventsStore.self) private var events
    @Environment(FamilyStore.self) private var family

    @State private var search = ""
    @State private var typeFilter: TypeFilter = .all
    @State private var statusFilter: TripStatus?
    @State private var showArchived = false
    @State private var path: [Trip] = []

    // Trip sheets
    @State private var showNewTrip = false
    @State private var manageSheet: ManageSheet?
    // Event sheets
    @State private var editing: FamilyEvent?
    @State private var isCreatingEvent = false
    @State private var makeEventFor: FamilyEvent?
    @State private var linkingEvent: FamilyEvent?

    @AppStorage("events.showBirthdays") private var showBirthdays = true
    @AppStorage("events.showHolidays")  private var showHolidays  = true

    private enum ManageSheet: Int, Identifiable { case destinations, places; var id: Int { rawValue } }

    /// Which kinds of item to show. "Countdowns" covers every non-trip
    /// FamilyEvent — both things you'll attend and pure countdowns you're just
    /// tracking. Persisted only in memory (resets each launch).
    private enum TypeFilter: String, CaseIterable, Identifiable {
        case all = "All", trips = "Trips", countdowns = "Countdowns"
        var id: String { rawValue }
    }

    /// A trip or an event, so both can share one sorted list.
    private enum BoardItem: Identifiable {
        case trip(Trip)
        case event(FamilyEvent)
        var id: String {
            switch self {
            case .trip(let t):  return "trip-\(t.id.uuidString)"
            case .event(let e): return "event-\(e.id.uuidString)"
            }
        }
    }

    private var canEdit: Bool { family.currentMember?.role == .admin }
    private var showsTrips: Bool { typeFilter != .countdowns }
    private var showsEvents: Bool { typeFilter != .trips }

    // MARK: - Matching (search + status)

    private func tripMatches(_ t: Trip) -> Bool {
        let s = search.trimmingCharacters(in: .whitespaces).lowercased()
        let textOK = s.isEmpty
            || t.name.lowercased().contains(s)
            || (t.destination?.lowercased().contains(s) ?? false)
            || (t.departDate.map { Trip.yearFormatter.string(from: $0).contains(s) } ?? false)
        let statusOK = statusFilter == nil || t.status == statusFilter
        return textOK && statusOK
    }

    private func eventMatches(_ e: FamilyEvent) -> Bool {
        let s = search.trimmingCharacters(in: .whitespaces).lowercased()
        return s.isEmpty
            || e.title.lowercased().contains(s)
            || (e.eventType?.lowercased().contains(s) ?? false)
    }

    // MARK: - Birthday synthesis

    /// Synthetic FamilyEvent instances derived from FamilyMember.birthday.
    /// These are never persisted — they live only in memory for display.
    private var birthdayEvents: [FamilyEvent] {
        guard let familyID = family.members.first?.familyID else { return [] }
        return family.members.compactMap { member in
            guard let birthday = member.birthday else { return nil }
            return FamilyEvent(
                id: member.id,               // stable, member-scoped ID
                familyID: familyID,
                title: "\(member.name)'s Birthday",
                eventType: FamilyEventType.birthday.rawValue,
                eventDate: birthday,
                isAnnual: true,
                emoji: "🎂"
            )
        }
    }

    /// Match key so a real event "covers" a synthetic birthday when they share a
    /// title and the same month/day (a birthday you've turned into an event).
    private func eventKey(_ e: FamilyEvent) -> String {
        let c = Calendar.current.dateComponents([.month, .day], from: e.eventDate)
        return "\(e.title.lowercased())|\(c.month ?? 0)-\(c.day ?? 0)"
    }

    /// Hide birthday / holiday events when their toggle is off.
    private func passesFilter(_ event: FamilyEvent) -> Bool {
        if event.eventType == FamilyEventType.birthday.rawValue { return showBirthdays }
        if event.eventType == FamilyEventType.holiday.rawValue  { return showHolidays }
        return true
    }

    private var memberIDs: Set<UUID> { Set(family.members.map(\.id)) }
    /// True if this event is a member-birthday synthetic (not editable / deletable).
    private func isSynthetic(_ event: FamilyEvent) -> Bool {
        event.eventType == FamilyEventType.birthday.rawValue && memberIDs.contains(event.id)
    }

    /// Upcoming events: DB upcoming + synthetic birthdays not already covered by a
    /// real event, passing the birthday/holiday toggles and the search.
    private var upcomingEvents: [FamilyEvent] {
        let realKeys = Set(events.upcoming.map(eventKey))
        let synthetic = birthdayEvents.filter { !realKeys.contains(eventKey($0)) }
        return (events.upcoming + synthetic)
            .filter(passesFilter)
            .filter(eventMatches)
            .sorted { $0.daysAway < $1.daysAway }
    }

    // MARK: - Merged sections

    /// Upcoming trips + upcoming events, sorted by how soon they are.
    private var upcomingItems: [BoardItem] {
        var out: [BoardItem] = []
        if showsTrips { out += trips.upcoming.filter(tripMatches).map(BoardItem.trip) }
        if showsEvents { out += upcomingEvents.map(BoardItem.event) }
        return out.sorted { soonKey($0) < soonKey($1) }
    }
    private func soonKey(_ item: BoardItem) -> Int {
        switch item {
        case .trip(let t):  return t.daysUntilDeparture ?? Int.max
        case .event(let e): return e.daysAway
        }
    }

    /// Past trips + event memories, most recent first.
    private var pastItems: [BoardItem] {
        var out: [BoardItem] = []
        if showsTrips { out += trips.past.filter(tripMatches).map(BoardItem.trip) }
        if showsEvents {
            out += events.memories.filter(passesFilter).filter(eventMatches).map(BoardItem.event)
        }
        return out.sorted { pastKey($0) > pastKey($1) }
    }
    private func pastKey(_ item: BoardItem) -> Date {
        switch item {
        case .trip(let t):  return t.departDate ?? .distantPast
        case .event(let e): return e.eventDate
        }
    }

    /// "Not going" trips (never events), collapsed by default.
    private var archivedTrips: [Trip] {
        guard showsTrips else { return [] }
        return trips.archivedTrips.filter(tripMatches)
    }

    private var pastSectionTitle: String {
        switch typeFilter {
        case .trips:             return "Past"
        case .countdowns, .all:  return "Past & Memories"
        }
    }

    // MARK: - Chips

    private var hasBirthdays: Bool { !birthdayEvents.isEmpty }
    private var hasHolidays: Bool {
        events.events.contains { $0.eventType == FamilyEventType.holiday.rawValue }
    }
    private var showChips: Bool { showsEvents && (hasBirthdays || hasHolidays) }

    // MARK: - Actions

    private func archive(_ trip: Trip) async {
        await events.deleteForTrip(trip.id)
        await trips.setArchived(trip, true)
    }
    private func restore(_ trip: Trip) async {
        await trips.setArchived(trip, false)
        await events.syncCountdown(forTripID: trip.id, familyID: trip.familyID,
                                   name: trip.name, departDate: trip.departDate,
                                   createdBy: family.currentMember?.userID)
    }
    private func tap(_ event: FamilyEvent) {
        if let tid = event.tripID, let trip = trips.trips.first(where: { $0.id == tid }) {
            path.append(trip)
        } else if canEdit {
            makeEventFor = event
        }
    }

    // MARK: - Body

    private var isEverythingEmpty: Bool {
        trips.trips.isEmpty && events.events.isEmpty && birthdayEvents.isEmpty
    }

    var body: some View {
        // Path-based navigation for trips so event taps (which open a linked trip
        // programmatically) and trip-row taps share one stack — mixing a bound
        // path with a destination-based NavigationLink previously rendered a
        // duplicate nav bar / double back button.
        NavigationStack(path: $path) {
            content
                .navigationTitle("Events")
                .searchable(text: $search, prompt: "Search trips & events")
                .navigationDestination(for: Trip.self) { TripDetailView(trip: $0) }
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Menu {
                            Button("Destinations", systemImage: "mappin.and.ellipse") { manageSheet = .destinations }
                            Button("Places", systemImage: "map") { manageSheet = .places }
                        } label: { Image(systemName: "map") }
                    }
                    if showsTrips {
                        ToolbarItem(placement: .primaryAction) {
                            Menu {
                                Button { statusFilter = nil } label: {
                                    Label("All statuses", systemImage: statusFilter == nil ? "checkmark" : "line.3.horizontal")
                                }
                                ForEach(TripStatus.allCases, id: \.self) { s in
                                    Button { statusFilter = s } label: {
                                        Label(s.label, systemImage: statusFilter == s ? "checkmark" : s.systemImage)
                                    }
                                }
                            } label: {
                                Image(systemName: statusFilter == nil ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
                            }
                        }
                    }
                    ToolbarItem(placement: .primaryAction) {
                        Menu {
                            Button { showNewTrip = true } label: { Label("New Trip", systemImage: "airplane") }
                            if canEdit {
                                Button { isCreatingEvent = true } label: { Label("New Countdown", systemImage: "calendar.badge.plus") }
                            }
                        } label: { Image(systemName: "plus") }
                        .accessibilityLabel("Add")
                    }
                }
                .task {
                    if trips.trips.isEmpty { await trips.load() }
                    if events.events.isEmpty { await events.load() }
                    if family.members.isEmpty { await family.load() }
                }
                .sheet(isPresented: $showNewTrip) {
                    if let familyID = family.familyID {
                        TripEditView(trip: Trip(familyID: familyID, name: ""))
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
                .sheet(item: $editing) { EventEditView(existing: $0) }
                .sheet(isPresented: $isCreatingEvent) { EventEditView(existing: nil) }
                .sheet(item: $linkingEvent) { LinkTripSheet(event: $0) }
                .eventActions(event: $makeEventFor,
                              onOpenTrip: { path.append($0) },
                              onLinkTrip: { linkingEvent = $0 },
                              onEditCountdown: { editing = $0 })
        }
    }

    @ViewBuilder
    private var content: some View {
        if (trips.isLoading || events.isLoading) && isEverythingEmpty {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if isEverythingEmpty {
            ContentUnavailableView {
                Label("Nothing planned yet", systemImage: "calendar")
            } description: {
                Text("Add a trip or a one-day event to start a countdown.")
            } actions: {
                Button("New Trip") { showNewTrip = true }
                    .buttonStyle(.borderedProminent)
                if canEdit {
                    Button("New Countdown") { isCreatingEvent = true }
                }
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
            .padding(.top, 8)
            .padding(.bottom, showChips ? 4 : 8)

            if showChips {
                filterBar.background(Color(.systemGroupedBackground))
            }

            if upcomingItems.isEmpty && pastItems.isEmpty && archivedTrips.isEmpty {
                filteredEmpty
            } else {
                List {
                    if !upcomingItems.isEmpty {
                        Section("Upcoming") {
                            ForEach(upcomingItems) { row(for: $0, isUpcoming: true) }
                        }
                    }
                    if !pastItems.isEmpty {
                        Section(pastSectionTitle) {
                            ForEach(pastItems) { row(for: $0, isUpcoming: false) }
                        }
                    }
                    if !archivedTrips.isEmpty {
                        Section {
                            if showArchived {
                                ForEach(archivedTrips) { trip in
                                    tripRow(trip)
                                }
                            }
                        } header: {
                            Button {
                                withAnimation { showArchived.toggle() }
                            } label: {
                                HStack {
                                    Text("Not going (\(archivedTrips.count))")
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
                .refreshable { await trips.load(); await events.load() }
            }
        }
    }

    /// Shown inside `board` (Picker still above) when the current filter/search
    /// matches nothing but data exists elsewhere.
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
        case .trips:      return "No trips match. Try another filter above."
        case .countdowns: return "No countdowns match. Try another filter above."
        case .all:        return "Nothing matches the current filters."
        }
    }

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                if hasBirthdays {
                    EventFilterChip(label: "Birthdays", icon: "birthday.cake.fill",
                                    isActive: showBirthdays, tint: .pink) {
                        showBirthdays.toggle()
                    }
                }
                if hasHolidays {
                    EventFilterChip(label: "Holidays", icon: "star.fill",
                                    isActive: showHolidays, tint: .orange) {
                        showHolidays.toggle()
                    }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
    }

    // MARK: - Rows

    @ViewBuilder
    private func row(for item: BoardItem, isUpcoming: Bool) -> some View {
        switch item {
        case .trip(let trip):   tripRow(trip)
        case .event(let event): eventRow(event, isUpcoming: isUpcoming)
        }
    }

    private func tripRow(_ trip: Trip) -> some View {
        NavigationLink(value: trip) {
            TripRowLabel(trip: trip)
        }
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

    private func eventRow(_ event: FamilyEvent, isUpcoming: Bool) -> some View {
        let synthetic = isSynthetic(event)
        let linked = event.tripID != nil && trips.trips.contains { $0.id == event.tripID }
        return Button {
            tap(event)
        } label: {
            EventRow(event: event, isUpcoming: isUpcoming, linkedToTrip: linked)
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing) {
            if canEdit && !synthetic {
                Button(role: .destructive) {
                    Task { await events.delete(event) }
                } label: {
                    Label("Delete", systemImage: "trash")
                }
                Button {
                    editing = event
                } label: {
                    Label("Edit", systemImage: "pencil")
                }
                .tint(.blue)
            }
        }
    }
}

// MARK: - Link-to-trip picker

private struct LinkTripSheet: View {
    let event: FamilyEvent
    @Environment(EventsStore.self) private var events
    @Environment(TripsStore.self) private var trips
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if trips.trips.isEmpty {
                    ContentUnavailableView("No trips yet", systemImage: "airplane",
                        description: Text("Create a trip first, then link it here."))
                } else {
                    ForEach(trips.trips) { trip in
                        Button {
                            Task { await events.linkTrip(event, tripID: trip.id); dismiss() }
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "airplane").foregroundStyle(Theme.Colors.brand).frame(width: 24)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(trip.name).foregroundStyle(.primary)
                                    if let depart = trip.departDate {
                                        Text(depart, format: .dateTime.month(.abbreviated).day().year())
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                if event.tripID == trip.id {
                                    Image(systemName: "checkmark").foregroundStyle(Theme.Colors.brand)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Link a Trip")
            #if !targetEnvironment(macCatalyst)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                if event.tripID != nil {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Unlink", role: .destructive) {
                            Task { await events.linkTrip(event, tripID: nil); dismiss() }
                        }
                    }
                }
            }
            .task { if trips.trips.isEmpty { await trips.load() } }
        }
    }
}

// MARK: - Filter chip

private struct EventFilterChip: View {
    let label: String
    let icon: String
    let isActive: Bool
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon).font(.caption)
                Text(label).font(.caption.weight(.medium))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(isActive ? tint.opacity(0.18) : Color(.tertiarySystemFill), in: Capsule())
            .foregroundStyle(isActive ? tint : .secondary)
            .overlay(Capsule().stroke(isActive ? tint.opacity(0.4) : .clear, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Event row

private struct EventRow: View {
    let event: FamilyEvent
    let isUpcoming: Bool
    var linkedToTrip: Bool = false

    var body: some View {
        HStack(spacing: 12) {
            if let emoji = event.emoji, !emoji.isEmpty {
                Text(emoji).font(.system(size: 36))
            } else {
                Image(systemName: defaultIcon)
                    .font(.title2)
                    .foregroundStyle(defaultIconColor)
                    .frame(width: 36)
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    Text(event.title).font(.headline)
                    if linkedToTrip {
                        Image(systemName: "airplane.circle.fill")
                            .font(.caption).foregroundStyle(Theme.Colors.brand)
                    }
                }
                HStack(spacing: 6) {
                    Text(dateLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let type = event.eventType {
                        Text(type)
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color(.tertiarySystemFill), in: Capsule())
                            .foregroundStyle(.secondary)
                    }
                    // Age / anniversary milestone label
                    if let years = event.yearsAtNextOccurrence, isUpcoming {
                        if event.eventType == FamilyEventType.birthday.rawValue {
                            Text("Turns \(years)")
                                .font(.caption2.weight(.semibold))
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Color.pink.opacity(0.15), in: Capsule())
                                .foregroundStyle(.pink)
                        } else if event.eventType == FamilyEventType.anniversary.rawValue {
                            Text("\(ordinal(years)) anniversary")
                                .font(.caption2.weight(.semibold))
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Color.purple.opacity(0.15), in: Capsule())
                                .foregroundStyle(.purple)
                        }
                    }
                }
            }

            Spacer()

            if isUpcoming {
                VStack(alignment: .trailing, spacing: 0) {
                    Text("\(event.daysAway)")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(event.daysAway <= 7 ? .orange : .primary)
                    Text(event.daysAway == 1 ? "day" : "days")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Helpers

    private var dateLabel: String {
        let f = DateFormatter()
        if event.isAnnual {
            // Show just month + day (no year) since it repeats
            f.dateFormat = "MMM d"
            return f.string(from: event.nextOccurrenceDate)
        } else {
            f.dateFormat = "EEE MMM d, yyyy"
            return f.string(from: event.eventDate)
        }
    }

    private var defaultIcon: String {
        switch event.eventType {
        case FamilyEventType.birthday.rawValue:    return "birthday.cake.fill"
        case FamilyEventType.anniversary.rawValue: return "heart.fill"
        case FamilyEventType.vacation.rawValue:    return "airplane"
        case FamilyEventType.holiday.rawValue:     return "star.fill"
        default:                                   return "party.popper.fill"
        }
    }

    private var defaultIconColor: Color {
        switch event.eventType {
        case FamilyEventType.birthday.rawValue:    return .pink
        case FamilyEventType.anniversary.rawValue: return .purple
        case FamilyEventType.vacation.rawValue:    return .blue
        case FamilyEventType.holiday.rawValue:     return .orange
        default:                                   return .orange
        }
    }

    /// English ordinal suffix: 1st, 2nd, 3rd, 4th …
    private func ordinal(_ n: Int) -> String {
        let suffix: String
        switch n % 100 {
        case 11, 12, 13: suffix = "th"
        default:
            switch n % 10 {
            case 1: suffix = "st"
            case 2: suffix = "nd"
            case 3: suffix = "rd"
            default: suffix = "th"
            }
        }
        return "\(n)\(suffix)"
    }
}
