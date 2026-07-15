import SwiftUI

/// The "countdown board" — upcoming dated milestones with a live day-away
/// counter, plus past Memories. Member birthdays are synthesized in-memory
/// from `fam_family_members.birthday` (never persisted).
struct EventsListView: View {
    @Environment(EventsStore.self) private var events
    @Environment(FamilyStore.self) private var family
    @Environment(TripsStore.self) private var trips

    @State private var editing: FamilyEvent?
    @State private var isCreating = false
    @State private var path: [Trip] = []
    @State private var makeEventFor: FamilyEvent?
    @State private var linkingEvent: FamilyEvent?

    @AppStorage("events.showBirthdays") private var showBirthdays = true
    @AppStorage("events.showHolidays")  private var showHolidays  = true

    private var canEdit: Bool { family.currentMember?.role == .admin }

    /// Hide birthday / holiday events when their toggle is off.
    private func passesFilter(_ event: FamilyEvent) -> Bool {
        if event.eventType == FamilyEventType.birthday.rawValue { return showBirthdays }
        if event.eventType == FamilyEventType.holiday.rawValue  { return showHolidays }
        return true
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

    /// Birthdays are always annual, so daysAway ≥ 0. Merge with DB upcoming and sort.
    private var allUpcoming: [FamilyEvent] {
        (events.upcoming + birthdayEvents)
            .filter(passesFilter)
            .sorted { $0.daysAway < $1.daysAway }
    }

    /// True if this event is a member-birthday synthetic (not editable / deletable).
    private var memberIDs: Set<UUID> { Set(family.members.map(\.id)) }
    private func isSynthetic(_ event: FamilyEvent) -> Bool {
        event.eventType == FamilyEventType.birthday.rawValue && memberIDs.contains(event.id)
    }

    var body: some View {
        // Value/path-based navigation — the previous `.navigationDestination(item:)`
        // on the load-swapping content rendered a duplicate nav bar / double back
        // button. Pushing Trip values onto an explicit path is the robust fix.
        NavigationStack(path: $path) {
            content
                .navigationTitle("Countdown")
                .toolbar {
                    if canEdit {
                        ToolbarItem(placement: .primaryAction) {
                            Button {
                                isCreating = true
                            } label: {
                                Image(systemName: "plus")
                            }
                            .accessibilityLabel("New event")
                        }
                    }
                }
                .task {
                    if events.events.isEmpty { await events.load() }
                    if family.members.isEmpty { await family.load() }
                    if trips.trips.isEmpty { await trips.load() }
                }
                .navigationDestination(for: Trip.self) { TripDetailView(trip: $0) }
                .sheet(item: $editing) { event in
                    EventEditView(existing: event)
                }
                .sheet(isPresented: $isCreating) {
                    EventEditView(existing: nil)
                }
                .sheet(item: $linkingEvent) { event in
                    LinkTripSheet(event: event)
                }
                .eventActions(event: $makeEventFor,
                              onOpenTrip: { path.append($0) },
                              onLinkTrip: { linkingEvent = $0 },
                              onEditCountdown: { editing = $0 })
        }
    }

    private func tap(_ event: FamilyEvent, synthetic: Bool) {
        if let tid = event.tripID, let trip = trips.trips.first(where: { $0.id == tid }) {
            path.append(trip)
        } else if canEdit {
            makeEventFor = event
        }
    }

    @ViewBuilder
    private var content: some View {
        if events.isLoading && events.events.isEmpty && birthdayEvents.isEmpty {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if events.events.isEmpty && birthdayEvents.isEmpty {
            ContentUnavailableView(
                "No dates yet",
                systemImage: "calendar.badge.clock",
                description: Text(canEdit
                    ? "Tap + to add the next thing worth being excited about."
                    : "Nothing on the countdown board yet.")
            )
        } else {
            list
        }
    }

    /// Show the filter bar only when there are birthdays or holidays to filter.
    private var hasBirthdays: Bool { !birthdayEvents.isEmpty }
    private var hasHolidays: Bool {
        (events.upcoming + events.memories).contains {
            $0.eventType == FamilyEventType.holiday.rawValue
        }
    }

    private var filteredMemories: [FamilyEvent] {
        events.memories.filter(passesFilter)
    }

    private var list: some View {
        VStack(spacing: 0) {
            if hasBirthdays || hasHolidays {
                filterBar
                    .background(Color(.systemGroupedBackground))
            }
            List {
                if !allUpcoming.isEmpty {
                    Section("Upcoming") {
                        ForEach(allUpcoming) { event in
                            row(for: event, isUpcoming: true)
                        }
                    }
                }
                if !filteredMemories.isEmpty {
                    Section("Memories") {
                        ForEach(filteredMemories) { event in
                            row(for: event, isUpcoming: false)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .refreshable { await events.load() }
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

    private func row(for event: FamilyEvent, isUpcoming: Bool) -> some View {
        let synthetic = isSynthetic(event)
        let linked = event.tripID != nil && trips.trips.contains { $0.id == event.tripID }
        return Button {
            tap(event, synthetic: synthetic)
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

// MARK: - Row

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
