import SwiftUI

/// The landing tab — a heartbeat across everything: the next trip and its
/// countdown, upcoming reservations, this week's dates, and the nearest
/// countdown milestone.
struct HomeView: View {
    @Environment(TripsStore.self) private var trips
    @Environment(DateNightsStore.self) private var dates
    @Environment(EventsStore.self) private var events
    @Environment(FamilyStore.self) private var family
    @Environment(DashboardStore.self) private var dashboard
    @AppStorage("notifications.enabled") private var notificationsEnabled = true
    @AppStorage("events.showBirthdays") private var showBirthdays = true
    @AppStorage("events.showHolidays") private var showHolidays = true

    @State private var openTrip: Trip?
    @State private var openCountdown: CountdownRoute?
    @State private var showSettings = false
    @State private var showNotes = false


    // AppShell owns the NavigationStack for this tab; this root is bare. Trip
    // pushes go through `openTrip` + .navigationDestination(item:) so no path
    // binding (which the shared shell doesn't expose) is needed.
    var body: some View {
        ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    if let trip = nextTrip {
                        nextTripCard(trip)
                    }
                    if !dashboard.upcomingReservations.isEmpty {
                        reservationsSection
                    }
                    if !weekDates.isEmpty {
                        datesSection
                    }
                    if !comingUp.isEmpty {
                        comingUpSection
                    }
                    if isEmpty {
                        ContentUnavailableView(
                            "Nothing scheduled yet",
                            systemImage: "sparkles",
                            description: Text("Plan a trip or a date, or add a countdown — it'll show up here."))
                            .padding(.top, 40)
                    }
                }
                .padding()
                // Readable width on iPad/regular: the dashboard is a column of
                // cards, not a form, but letting it stretch to a 13" iPad's full
                // width reads as an iPhone screen pulled wide rather than a
                // restructured layout. Cap and center instead.
                .frame(maxWidth: 672)
                .frame(maxWidth: .infinity)
            }
            .navigationTitle(greeting)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button { showNotes = true } label: { Label("Notes", systemImage: "note.text") }
                        Button { showSettings = true } label: { Label("Settings", systemImage: "gearshape") }
                    } label: {
                        Label("More", systemImage: "ellipsis.circle")
                    }
                }
            }
        .sheet(isPresented: $showNotes) { NotesTabView() }
        .sheet(isPresented: $showSettings) { SettingsView() }
        .navigationDestination(item: $openTrip) { TripDetailView(trip: $0) }
        .navigationDestination(item: $openCountdown) { route in
            CountdownDetailView(event: route.event, isFromPeople: route.isFromPeople)
        }
        .task {
            if trips.trips.isEmpty { await trips.load() }
            if dates.dates.isEmpty { await dates.load() }
            if events.events.isEmpty { await events.load() }
            if family.members.isEmpty { await family.load() }
            await dashboard.load()
            await NotificationManager.sync(trips: trips.upcoming,
                                           reservations: dashboard.upcomingReservations,
                                           dates: dates.upcoming,
                                           countdowns: allCountdowns,
                                           enabled: notificationsEnabled)
        }
        .refreshable {
            await trips.load(); await dates.load(); await events.load(); await dashboard.load()
        }
    }

    // MARK: Derived

    private var greeting: String {
        let name = family.currentMember?.name.split(separator: " ").first.map(String.init)
        return name.map { "Hi, \($0)" } ?? "Home"
    }

    private var nextTrip: Trip? { trips.upcoming.first }

    /// Dates scheduled within the next 7 days.
    private var weekDates: [DateNight] {
        let weekOut = Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date()
        return dates.upcoming.filter { ($0.scheduledAt ?? .distantFuture) <= weekOut }
    }

    /// Everything counting down — the same list the Countdowns tab shows.
    private var allCountdowns: [Countdown] {
        CountdownBuilder.build(
            trips: trips.trips, events: events.events, birthdays: family.birthdayEvents,
            destinationName: { trips.destination(for: $0)?.name ?? $0.destination?.nilIfBlank },
            showBirthdays: showBirthdays, showHolidays: showHolidays)
    }

    /// The next four, minus the plan the hero card already shows. Replaces a
    /// "Birthdays" card and an "Events" card that each showed two — and the
    /// Events one was mostly the trip copies syncCountdown writes, so a trip in
    /// the hero card also appeared underneath it.
    private var comingUp: [Countdown] {
        Array(allCountdowns.filter { $0.trip?.id == nil || $0.trip?.id != nextTrip?.id }.prefix(4))
    }

    private var isEmpty: Bool {
        nextTrip == nil && dashboard.upcomingReservations.isEmpty && weekDates.isEmpty
            && comingUp.isEmpty
    }

    // MARK: Cards

    private func nextTripCard(_ trip: Trip) -> some View {
        NavigationLink { TripDetailView(trip: trip) } label: {
            VStack(alignment: .leading, spacing: 0) {
                CoverImage(cover: trip.coverPhotoURL,
                           focus: UnitPoint(x: trip.coverFocusX, y: trip.coverFocusY)) {
                    LinearGradient(colors: [Theme.Colors.brand.opacity(0.7), Theme.Colors.brand.opacity(0.35)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                }
                .frame(height: 150)
                .frame(maxWidth: .infinity)
                .clipped()
                .overlay(alignment: .bottomLeading) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(trip.name).font(.title3.bold()).foregroundStyle(.white)
                        if let dest = trips.destination(for: trip)?.name ?? trip.destination {
                            Text(dest).font(.subheadline).foregroundStyle(.white.opacity(0.9))
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(LinearGradient(colors: [.clear, .black.opacity(0.55)],
                                               startPoint: .top, endPoint: .bottom))
                }

                HStack {
                    Label(tripCountdownText(trip), systemImage: "timer")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.Colors.brand)
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                }
                .padding(12)
            }
            .background(Color(.secondarySystemGroupedBackground))
            // Clip the whole card (cover, dark text overlay, and background) to one
            // rounded shape so the cover's corners match the card instead of the
            // square-cornered image poking past the rounded background.
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
    }

    private func tripCountdownText(_ trip: Trip) -> String {
        guard let depart = trip.departDate else { return "Someday" }
        let cal = Calendar.current
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: Date()),
                                      to: cal.startOfDay(for: depart)).day ?? 0
        if days > 1 { return "\(trip.name) in \(days) days" }
        if days == 1 { return "Tomorrow!" }
        if days == 0 { return "Today!" }
        // Trip has departed — show return countdown if available.
        if let ret = trip.returnDate {
            let back = cal.dateComponents([.day], from: cal.startOfDay(for: Date()),
                                          to: cal.startOfDay(for: ret)).day ?? 0
            if back >= 0 { return back == 0 ? "Back today" : "Home in \(back) day\(back == 1 ? "" : "s")" }
        }
        return "Happening now"
    }

    private var reservationsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Upcoming").font(.headline)
            ForEach(dashboard.upcomingReservations) { res in
                HStack(spacing: 12) {
                    Image(systemName: res.type.systemImage)
                        .foregroundStyle(Theme.Colors.brand).frame(width: 26)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(res.title.isEmpty ? res.type.label : res.title).font(.subheadline.weight(.medium))
                        if let name = trips.trips.first(where: { $0.id == res.tripID })?.name {
                            Text(name).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    if let start = res.startAt {
                        Text(start, format: .dateTime.month(.abbreviated).day().hour().minute())
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    private var datesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("This week's dates").font(.headline)
            ForEach(weekDates) { d in
                HStack(spacing: 12) {
                    Image(systemName: "heart.fill").foregroundStyle(.pink).frame(width: 26)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(d.title).font(.subheadline.weight(.medium))
                        if let loc = d.primaryLocationName {
                            Text(loc).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    if let when = d.scheduledAt {
                        Text(when, format: .dateTime.weekday().hour().minute())
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    private var comingUpSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Coming up", systemImage: "hourglass")
                    .font(.headline).foregroundStyle(Theme.Colors.brand)
                Spacer()
                NavigationLink { CountdownsView() } label: {
                    Text("See all").font(.subheadline.weight(.medium))
                }
            }
            ForEach(comingUp) { item in
                Button { open(item) } label: { CountdownRow(item: item, showsChevron: true) }
                    .buttonStyle(.plain)
                if item.id != comingUp.last?.id { Divider() }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    /// A plan opens; a countdown or a People birthday opens its detail — the
    /// live clock, the time and the note.
    private func open(_ item: Countdown) {
        switch item.source {
        case .plan(let trip):                       openTrip = trip
        case .countdown(let e):                     openCountdown = .countdown(e)
        case .birthday(let e):                      openCountdown = .birthday(e)
        }
    }
}
