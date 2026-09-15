import SwiftUI
import AppShellKit

/// Everything counting down, in one place: pure countdowns (anniversaries,
/// holidays, a race), People birthdays, and the trips and events you're planning.
///
/// A plan's countdown is the plan itself — tapping it opens the trip or party.
/// Before this, countdowns shared the Events board with trips under an
/// All/Trips/Countdowns picker, every dated trip appeared there twice, and Home
/// showed only the next two. See `Countdown` for how the sources are merged.
///
/// A bare root: as a tab, AppShell owns the NavigationStack; pushed from Home's
/// "See all" it rides Home's. So plan rows use `NavigationLink { … }` (not a
/// value-based destination, which only works reliably at a stack root), and the
/// plan created from "Plan something around it" opens in a sheet.
struct CountdownsView: View {
    @Environment(TripsStore.self) private var trips
    @Environment(EventsStore.self) private var events
    @Environment(FamilyStore.self) private var family
    // Shared with the Plans board's old chips so a choice made there carries over.
    @AppStorage("events.showBirthdays") private var showBirthdays = true
    @AppStorage("events.showHolidays") private var showHolidays = true
    @AppStorage("countdowns.showPeriods") private var showPeriods = true

    @State private var filter: Filter = .all
    @State private var editing: FamilyEvent?
    @State private var isCreatingCountdown = false
    @State private var newKind: PlanKind?
    @State private var planFrom: FamilyEvent?
    @State private var openedTrip: Trip?
    @State private var showPast = false
    @State private var search = ""

    enum Filter: String, CaseIterable, Identifiable {
        case all = "All", countdowns = "Countdowns", trips = "Trips", events = "Events"
        var id: String { rawValue }
    }

    private var canEdit: Bool { family.currentMember?.role == .admin }

    private var everything: [Countdown] {
        CountdownBuilder.build(
            trips: trips.trips, events: events.events, birthdays: family.birthdayEvents,
            destinationName: { trips.destination(for: $0)?.name ?? $0.destination?.nilIfBlank },
            showBirthdays: showBirthdays, showHolidays: showHolidays)
    }

    private var shown: [Countdown] {
        switch filter {
        case .all:        return everything
        case .countdowns: return everything.filter { $0.category == .countdowns }
        case .trips:      return everything.filter { $0.category == .trips }
        case .events:     return everything.filter { $0.category == .events }
        }
    }

    private func matchesSearch(_ c: Countdown) -> Bool {
        let s = search.trimmingCharacters(in: .whitespaces)
        guard !s.isEmpty else { return true }
        return [c.title, c.detail ?? "", c.badge].contains { $0.localizedCaseInsensitiveContains(s) }
    }

    var body: some View {
        let items = shown.filter(matchesSearch)
        VStack(spacing: 0) {
            // Kept above the list even when the filter matches nothing, so the
            // control that emptied it is always there to undo it.
            Picker("Show", selection: $filter) {
                ForEach(Filter.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.vertical, 10)

            // Past countdowns keep the list up even when nothing is ahead —
            // the empty state would otherwise leave them unreachable.
            if items.isEmpty && pastCountdowns.isEmpty && !search.isEmpty {
                ContentUnavailableView.search
            } else if items.isEmpty && pastCountdowns.isEmpty {
                emptyState
            } else {
                list(items)
            }
        }
        .frame(maxWidth: 760)
        .frame(maxWidth: .infinity)
        .background(FamilyPalette.groundGrouped)
        .navigationTitle("Countdowns")
        .searchable(text: $search, prompt: "Search countdowns")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Menu {
                    Toggle(isOn: $showBirthdays) { Label("Birthdays from People", systemImage: "birthday.cake") }
                    Toggle(isOn: $showHolidays) { Label("Holidays", systemImage: "star") }
                    Toggle(isOn: $showPeriods) { Label("This month & year", systemImage: "chart.bar.fill") }
                } label: {
                    Label("Show", systemImage: "line.3.horizontal.decrease.circle")
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    if canEdit {
                        Button { isCreatingCountdown = true } label: {
                            Label("New Countdown", systemImage: "hourglass")
                        }
                        Divider()
                    }
                    ForEach(PlanKind.allCases) { k in
                        Button { newKind = k } label: { Label("New \(k.label)", systemImage: k.systemImage) }
                    }
                } label: {
                    Label("Add", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $isCreatingCountdown) { EventEditView(existing: nil) }
        .sheet(item: $editing) { EventEditView(existing: $0) }
        .sheet(item: $newKind) { k in
            if let familyID = family.familyID {
                TripEditView(trip: Trip(familyID: familyID, name: "", kind: k))
            } else {
                Text("Loading your family…").padding()
            }
        }
        .sheet(item: $openedTrip) { trip in
            NavigationStack { TripDetailView(trip: trip) }
        }
        .eventActions(event: $planFrom, allowLinkEdit: false, onOpenTrip: { openedTrip = $0 })
        .task {
            if trips.trips.isEmpty { await trips.load() }
            if events.events.isEmpty { await events.load() }
            if family.members.isEmpty { await family.load() }
        }
    }

    // MARK: - List

    private struct Bucket: Identifiable {
        let id: String
        let title: String
        let items: [Countdown]
    }

    /// The next one gets the hero card; the rest fall into time buckets.
    private func buckets(_ items: [Countdown]) -> [Bucket] {
        var now: [Countdown] = [], today: [Countdown] = [], week: [Countdown] = []
        var month: [Countdown] = [], later: [Countdown] = []
        for i in items {
            if i.isHappeningNow { now.append(i) }
            else if i.daysAway == 0 { today.append(i) }
            else if i.daysAway <= 7 { week.append(i) }
            else if i.daysAway <= 31 { month.append(i) }
            else { later.append(i) }
        }
        return [Bucket(id: "now", title: "Happening now", items: now),
                Bucket(id: "today", title: "Today", items: today),
                Bucket(id: "week", title: "This week", items: week),
                Bucket(id: "month", title: "This month", items: month),
                Bucket(id: "later", title: "Later", items: later)]
            .filter { !$0.items.isEmpty }
    }

    private func list(_ items: [Countdown]) -> some View {
        List {
            if let next = items.first {
                Section {
                    card(next, large: true)
                } header: {
                    Text("Next up")
                }
            }
            if showPeriods && filter == .all && search.trimmingCharacters(in: .whitespaces).isEmpty {
                Section("Month & year") {
                    PeriodCard(period: .month).cardRow()
                    PeriodCard(period: .year).cardRow()
                }
            }
            ForEach(buckets(Array(items.dropFirst()))) { bucket in
                Section(bucket.title) {
                    ForEach(bucket.items) { card($0, large: false) }
                }
            }
            if !pastCountdowns.isEmpty {
                pastSection
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .refreshable { await trips.load(); await events.load() }
    }

    /// Every countdown is a card that opens its detail: a plan opens the plan,
    /// a countdown or a People birthday opens CountdownDetailView. The link
    /// sits behind the card — a NavigationLink label draws a chevron, which
    /// reads as a stray arrow on a full-bleed photo.
    @ViewBuilder
    private func card(_ item: Countdown, large: Bool) -> some View {
        let linked = ZStack {
            NavigationLink { destination(item) } label: { EmptyView() }
                .opacity(0)
            CountdownCard(item: item, large: large)
        }
        .cardRow()
        switch item.source {
        case .countdown(let e):
            linked
                .contextMenu {
                    if canEdit {
                        Button("Edit countdown", systemImage: "pencil") { editing = e }
                        Button("Plan something around it…", systemImage: "calendar.badge.plus") { planFrom = e }
                        Button("Delete", systemImage: "trash", role: .destructive) {
                            Task { await events.delete(e) }
                        }
                    }
                }
                .swipeActions(edge: .trailing) {
                    if canEdit {
                        Button(role: .destructive) { Task { await events.delete(e) } } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
        case .birthday(let e):
            linked
                .contextMenu {
                    Button("Plan something around it…", systemImage: "calendar.badge.plus") { planFrom = e }
                }
        case .plan:
            linked
        }
    }

    @ViewBuilder
    private func destination(_ item: Countdown) -> some View {
        switch item.source {
        case .plan(let trip):     TripDetailView(trip: trip)
        case .countdown(let e):   CountdownDetailView(event: e)
        case .birthday(let e):    CountdownDetailView(event: e, isFromPeople: true)
        }
    }

    /// One-off countdowns whose day has gone by, newest first. (Annual ones
    /// never go past — they roll to next year.) Hidden under a header you tap,
    /// the way the Plans board keeps "Not going".
    private var pastCountdowns: [FamilyEvent] {
        guard filter == .all || filter == .countdowns else { return [] }
        return events.memories.filter { e in
            guard e.tripID == nil else { return false }
            if e.eventType == FamilyEventType.birthday.rawValue && !showBirthdays { return false }
            if e.eventType == FamilyEventType.holiday.rawValue && !showHolidays { return false }
            let s = search.trimmingCharacters(in: .whitespaces)
            return s.isEmpty || e.title.localizedCaseInsensitiveContains(s)
        }
    }

    private var pastSection: some View {
        Section {
            if showPast || !search.isEmpty {
                ForEach(pastCountdowns) { e in
                    NavigationLink { CountdownDetailView(event: e) } label: {
                        HStack(spacing: 12) {
                            Text(e.emoji?.nilIfBlank ?? "⏳").font(.title3)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(e.title).foregroundStyle(FamilyPalette.ink)
                                Text(CountdownFormat.date(e.eventDate))
                                    .font(.caption).foregroundStyle(FamilyPalette.inkSecondary)
                            }
                            Spacer()
                            Text("\(-e.daysAway)d ago")
                                .font(.caption).foregroundStyle(FamilyPalette.inkSecondary)
                        }
                        .contentShape(Rectangle())
                    }
                }
            }
        } header: {
            Button {
                withAnimation { showPast.toggle() }
            } label: {
                HStack {
                    Text("Past (\(pastCountdowns.count))")
                    Spacer()
                    Image(systemName: showPast ? "chevron.down" : "chevron.right").font(.caption)
                }
            }
            .foregroundStyle(FamilyPalette.inkSecondary)
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label(filter == .all ? "Nothing to count down to" : "No \(filter.rawValue.lowercased())",
                  systemImage: "hourglass")
        } description: {
            Text(filter == .all
                 ? "Add a countdown for an anniversary, a holiday, or anything you're looking forward to — or plan a trip or an event."
                 : "Nothing coming up here. Try another filter above.")
        } actions: {
            if filter != .trips && filter != .events && canEdit {
                Button("New Countdown") { isCreatingCountdown = true }
                    .buttonStyle(.borderedProminent)
            }
        }
        .frame(maxHeight: .infinity)
    }
}

// MARK: - Pieces shared with Home

/// A countdown row: icon, title, date and detail, and the number of days.
struct CountdownRow: View {
    let item: Countdown
    var showsChevron = false

    var body: some View {
        HStack(spacing: 12) {
            CountdownIcon(item: item, size: 38)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(FamilyPalette.ink)
                    .lineLimit(2)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(FamilyPalette.inkSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            CountdownNumber(item: item)
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(FamilyPalette.inkTertiary)
            }
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private var subtitle: String {
        CountdownFormat.subtitle(item)
    }
}

struct CountdownIcon: View {
    let item: Countdown
    var size: CGFloat = 38

    var body: some View {
        ZStack {
            Circle().fill(item.tint.opacity(0.15))
            if let emoji = item.emoji {
                Text(emoji).font(.system(size: size * 0.5))
            } else {
                Image(systemName: item.systemImage)
                    .font(.system(size: size * 0.42, weight: .semibold))
                    .foregroundStyle(item.tint)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// The trailing number: "12 days", "Today", or "Now · 3d left".
struct CountdownNumber: View {
    let item: Countdown

    var body: some View {
        VStack(alignment: .trailing, spacing: 0) {
            Text(CountdownFormat.value(item))
                .font(.system(.title2, design: .rounded).weight(.bold))
                .monospacedDigit()
                .foregroundStyle(isSoon ? item.tint : FamilyPalette.ink)
            if let unit = CountdownFormat.shortUnit(item) {
                Text(unit).font(.caption).foregroundStyle(FamilyPalette.inkSecondary)
            }
        }
    }

    private var isSoon: Bool { item.isHappeningNow || item.daysAway <= 7 }
}

enum CountdownFormat {
    static func value(_ item: Countdown) -> String {
        if item.isHappeningNow { return "Now" }
        if item.daysAway == 0 { return "Today" }
        return "\(item.daysAway)"
    }

    static func shortUnit(_ item: Countdown) -> String? {
        if item.isHappeningNow {
            return item.daysUntilEnd.map { $0 <= 0 ? "ends today" : "\($0)d left" }
        }
        if item.daysAway == 0 { return nil }
        return item.daysAway == 1 ? "day" : "days"
    }

    static func longUnit(_ item: Countdown) -> String? {
        if item.isHappeningNow {
            return item.daysUntilEnd.map { $0 <= 0 ? "ends today" : "\($0) day\($0 == 1 ? "" : "s") left" }
        }
        if item.daysAway == 0 { return nil }
        return item.daysAway == 1 ? "day to go" : "days to go"
    }

    /// "Sat, Sep 27 · 7:30 PM · Turns 34" — the time only when one is set.
    static func subtitle(_ item: Countdown) -> String {
        [date(item.date), TimeOfDay.label(item.time), item.detail].compactMap { $0 }.joined(separator: " · ")
    }

    /// "Sat, Sep 27" — with the year once it isn't this year.
    static func date(_ d: Date) -> String {
        let sameYear = Calendar.current.isDate(d, equalTo: Date(), toGranularity: .year)
        return sameYear
            ? d.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
            : d.formatted(.dateTime.month(.abbreviated).day().year())
    }
}

private extension View {
    /// A card sitting in a List row: full row width, no cell fill, no separator.
    func cardRow() -> some View {
        self
            .listRowInsets(EdgeInsets(top: 5, leading: 0, bottom: 5, trailing: 0))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
    }
}
