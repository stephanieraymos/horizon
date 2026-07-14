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
                    if let event = nextCountdown {
                        countdownCard(event)
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

    /// Synthetic member birthdays merged with DB events; nearest upcoming.
    private var nextCountdown: FamilyEvent? {
        var all = events.upcoming
        if let familyID = family.members.first?.familyID {
            all += family.members.compactMap { m in
                guard let b = m.birthday else { return nil }
                return FamilyEvent(id: m.id, familyID: familyID, title: "\(m.name)'s Birthday",
                                   eventType: FamilyEventType.birthday.rawValue, eventDate: b,
                                   isAnnual: true, emoji: "🎂")
            }
        }
        return all.min { $0.daysAway < $1.daysAway }
    }

    private var isEmpty: Bool {
        nextTrip == nil && dashboard.upcomingReservations.isEmpty && weekDates.isEmpty && nextCountdown == nil
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

    private func countdownCard(_ event: FamilyEvent) -> some View {
        HStack(spacing: 14) {
            if let emoji = event.emoji, !emoji.isEmpty {
                Text(emoji).font(.system(size: 34))
            } else {
                Image(systemName: "calendar.badge.clock").font(.title).foregroundStyle(Theme.Colors.brand)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(event.title).font(.subheadline.weight(.semibold))
                Text("Next countdown").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 0) {
                Text("\(event.daysAway)").font(.title2.bold())
                    .foregroundStyle(event.daysAway <= 7 ? .orange : .primary)
                Text(event.daysAway == 1 ? "day" : "days").font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }
}
