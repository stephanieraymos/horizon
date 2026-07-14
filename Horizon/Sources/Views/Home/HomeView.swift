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

    var body: some View {
        NavigationStack {
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
                    if !nextBirthdays.isEmpty {
                        countdownSection("Birthdays", systemImage: "birthday.cake.fill",
                                         tint: .pink, events: nextBirthdays)
                    }
                    if !nextEvents.isEmpty {
                        countdownSection("Events", systemImage: "calendar.badge.clock",
                                         tint: Theme.Colors.brand, events: nextEvents)
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
            }
            .navigationTitle(greeting)
            .task {
                if trips.trips.isEmpty { await trips.load() }
                if dates.dates.isEmpty { await dates.load() }
                if events.events.isEmpty { await events.load() }
                if family.members.isEmpty { await family.load() }
                await dashboard.load()
                await NotificationManager.sync(trips: trips.upcoming,
                                               reservations: dashboard.upcomingReservations,
                                               dates: dates.upcoming,
                                               enabled: notificationsEnabled)
            }
            .refreshable {
                await trips.load(); await dates.load(); await events.load(); await dashboard.load()
            }
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

    /// Next two upcoming member birthdays (synthetic from FamilyMember.birthday).
    private var nextBirthdays: [FamilyEvent] {
        guard let familyID = family.members.first?.familyID else { return [] }
        return family.members
            .compactMap { m -> FamilyEvent? in
                guard let b = m.birthday else { return nil }
                return FamilyEvent(id: m.id, familyID: familyID, title: "\(m.name)'s Birthday",
                                   eventType: FamilyEventType.birthday.rawValue, eventDate: b,
                                   isAnnual: true, emoji: "🎂")
            }
            .sorted { $0.daysAway < $1.daysAway }
            .prefix(2).map { $0 }
    }

    /// Next two upcoming non-birthday countdown events.
    private var nextEvents: [FamilyEvent] {
        events.upcoming
            .filter { $0.eventType != FamilyEventType.birthday.rawValue }
            .prefix(2).map { $0 }
    }

    private var isEmpty: Bool {
        nextTrip == nil && dashboard.upcomingReservations.isEmpty && weekDates.isEmpty
            && nextBirthdays.isEmpty && nextEvents.isEmpty
    }

    // MARK: Cards

    private func nextTripCard(_ trip: Trip) -> some View {
        NavigationLink { TripDetailView(trip: trip) } label: {
            VStack(alignment: .leading, spacing: 0) {
                CoverImage(cover: trip.coverPhotoURL) {
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
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
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

    private func countdownSection(_ title: String, systemImage: String, tint: Color,
                                  events: [FamilyEvent]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: systemImage).font(.headline).foregroundStyle(tint)
            ForEach(events) { event in
                if let tid = event.tripID, let trip = trips.trips.first(where: { $0.id == tid }) {
                    NavigationLink { TripDetailView(trip: trip) } label: { countdownRow(event, chevron: true) }
                        .buttonStyle(.plain)
                } else {
                    countdownRow(event, chevron: false)
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    private func countdownRow(_ event: FamilyEvent, chevron: Bool) -> some View {
        HStack(spacing: 12) {
            if let emoji = event.emoji, !emoji.isEmpty {
                Text(emoji).font(.system(size: 26))
            } else {
                Image(systemName: "calendar").font(.title3).foregroundStyle(.secondary).frame(width: 26)
            }
            Text(event.title).font(.subheadline.weight(.medium))
            Spacer()
            Text(event.daysAway == 0 ? "Today" : "\(event.daysAway)d")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(event.daysAway <= 7 ? .orange : .primary)
            if chevron {
                Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 3)
    }
}
