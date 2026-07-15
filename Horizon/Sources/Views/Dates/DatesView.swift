import SwiftUI

/// The Dates tab: date-night ideas → scheduled outings → rated memories.
/// Stops map to the shared `fam_places` library.
struct DatesView: View {
    @Environment(DateNightsStore.self) private var dates
    @Environment(FamilyStore.self) private var family

    @State private var editing: DateNight?
    @State private var creating = false

    var body: some View {
        NavigationStack {
            Group {
                if dates.dates.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 12) {
                            if !dates.upcoming.isEmpty {
                                sectionHeader("Upcoming", systemImage: "heart.fill", color: .pink)
                                if let hero = dates.upcoming.first {
                                    card(hero) { HeroDateCard(date: hero) }
                                }
                                ForEach(Array(dates.upcoming.dropFirst())) { d in
                                    card(d) { DateCard(date: d) }
                                }
                            }
                            if !dates.ideas.isEmpty {
                                sectionHeader("Ideas", systemImage: "lightbulb.fill", color: .yellow)
                                    .padding(.top, 6)
                                ForEach(dates.ideas) { d in card(d) { DateCard(date: d) } }
                            }
                            if !dates.past.isEmpty {
                                sectionHeader("Memories", systemImage: "sparkles", color: Theme.Colors.brand)
                                    .padding(.top, 6)
                                ForEach(dates.past) { d in card(d) { DateCard(date: d) } }
                            }
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 10)
                    }
                    .background(Color(.systemGroupedBackground).ignoresSafeArea())
                    .refreshable { await dates.load() }
                }
            }
            .navigationTitle("Dates")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { creating = true } label: { Image(systemName: "plus") }
                }
            }
            .task { if dates.dates.isEmpty { await dates.load() } }
            .sheet(item: $editing) { DateNightEditView(existing: $0) }
            .sheet(isPresented: $creating) { DateNightEditView(existing: nil) }
        }
    }

    private func card<Content: View>(_ d: DateNight, @ViewBuilder _ content: () -> Content) -> some View {
        Button { editing = d } label: { content() }
            .buttonStyle(.plain)
            .contextMenu {
                Button("Edit", systemImage: "pencil") { editing = d }
                Button("Delete", systemImage: "trash", role: .destructive) {
                    Task { await dates.delete(d) }
                }
            }
    }

    private func sectionHeader(_ title: String, systemImage: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage).foregroundStyle(color)
            Text(title).font(.title3.bold())
            Spacer()
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No dates yet", systemImage: "heart.text.square")
        } description: {
            Text("Save ideas for dates, then schedule them when you're ready.")
        } actions: {
            Button { creating = true } label: {
                Text("Add a date idea").fontWeight(.semibold)
            }
            .buttonStyle(.borderedProminent).tint(.pink)
        }
    }
}

// MARK: - Category styling

/// Icon + accent color per date "vibe". Unknown/empty falls back to a warm pink.
private func dateCategoryStyle(_ category: String?) -> (icon: String, color: Color) {
    switch DateNightCategory(rawValue: category ?? "") {
    case .dinner:    return ("fork.knife", .orange)
    case .activity:  return ("figure.walk", .teal)
    case .stayIn:    return ("sofa.fill", .indigo)
    case .adventure: return ("mountain.2.fill", .green)
    case .none:      return ("heart.fill", .pink)
    }
}

/// "Today" / "Tomorrow" / "in N days" for the next ~two months, else nil.
private func dateCountdownText(_ when: Date?) -> String? {
    guard let when else { return nil }
    let cal = Calendar.current
    let days = cal.dateComponents([.day], from: cal.startOfDay(for: Date()),
                                  to: cal.startOfDay(for: when)).day ?? 0
    switch days {
    case ..<0:   return nil
    case 0:      return "Today"
    case 1:      return "Tomorrow"
    case 2...60: return "in \(days) days"
    default:     return nil
    }
}

/// Featured card for the next upcoming date — a category-tinted gradient with a
/// countdown pill, so the "what's next" jumps out.
private struct HeroDateCard: View {
    let date: DateNight
    private var style: (icon: String, color: Color) { dateCategoryStyle(date.category) }

    var body: some View {
        ZStack {
            LinearGradient(colors: [style.color, style.color.opacity(0.6)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            LinearGradient(colors: [.clear, .black.opacity(0.28)],
                           startPoint: .center, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Label(date.category ?? "Date", systemImage: style.icon)
                        .font(.caption.weight(.semibold)).foregroundStyle(.white)
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(.white.opacity(0.22), in: Capsule())
                    Spacer()
                    if let cd = dateCountdownText(date.scheduledAt) {
                        Text(cd).font(.caption.weight(.bold)).foregroundStyle(.white)
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(.white.opacity(0.22), in: Capsule())
                    }
                }
                Spacer(minLength: 24)
                Text(date.title).font(.title2.bold()).foregroundStyle(.white).lineLimit(2)
                if date.primaryLocationName != nil || date.scheduledAt != nil {
                    HStack(spacing: 12) {
                        if let loc = date.primaryLocationName {
                            Label(loc, systemImage: "mappin.and.ellipse").lineLimit(1)
                        }
                        if let when = date.scheduledAt {
                            Label(when.formatted(.dateTime.weekday(.abbreviated).hour().minute()),
                                  systemImage: "clock")
                        }
                    }
                    .font(.caption).foregroundStyle(.white.opacity(0.95))
                    .padding(.top, 4)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
        .frame(height: 160)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(color: style.color.opacity(0.35), radius: 10, x: 0, y: 5)
    }
}

/// Standard elevated card for upcoming (beyond the hero), ideas, and memories.
private struct DateCard: View {
    let date: DateNight
    private var style: (icon: String, color: Color) { dateCategoryStyle(date.category) }

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12).fill(style.color.opacity(0.15))
                Image(systemName: style.icon).font(.title3).foregroundStyle(style.color)
            }
            .frame(width: 46, height: 46)

            VStack(alignment: .leading, spacing: 5) {
                Text(date.title).font(.headline).lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                FlowLayout(spacing: 6) {
                    if let cat = date.category {
                        Text(cat).font(.caption2.weight(.medium))
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(style.color.opacity(0.15), in: Capsule())
                            .foregroundStyle(style.color)
                    }
                    if let loc = date.primaryLocationName {
                        Label(loc, systemImage: "mappin.and.ellipse")
                            .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    if let dests = date.destinations, dests.count > 1 {
                        Text("\(dests.count) stops").font(.caption2).foregroundStyle(.tertiary)
                    }
                }
            }

            Spacer(minLength: 8)
            trailing.fixedSize()
        }
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.05), radius: 4, x: 0, y: 2)
    }

    @ViewBuilder private var trailing: some View {
        if date.isPast, let rating = date.rating {
            HStack(spacing: 1) {
                ForEach(1..<6) { i in
                    Image(systemName: i <= rating ? "star.fill" : "star").font(.caption2)
                }
            }
            .foregroundStyle(.orange)
        } else if let when = date.scheduledAt {
            VStack(alignment: .trailing, spacing: 2) {
                Text(when.formatted(.dateTime.month(.abbreviated).day()))
                    .font(.caption.weight(.semibold))
                Text(when.formatted(.dateTime.hour().minute()))
                    .font(.caption2).foregroundStyle(.secondary)
            }
        } else if date.ideaOnly {
            Image(systemName: "calendar.badge.plus")
                .font(.body).foregroundStyle(style.color)
        }
    }
}

// MARK: - Edit / Create Sheet

struct DateNightEditView: View {
    let existing: DateNight?

    @Environment(DateNightsStore.self) private var dates
    @Environment(FamilyStore.self) private var family
    @Environment(TripsStore.self) private var trips
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var category = DateNightCategory.dinner.rawValue
    @State private var destinations: [DateNightDestination] = []
    @State private var estCost = ""
    @State private var notes = ""
    @State private var hasSchedule = false
    @State private var scheduledAt = Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date()
    @State private var rating: Int = 0
    @State private var reviewNotes = ""
    @State private var isSaving = false

    // Location search sheet
    @State private var addingLocation = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Date idea") {
                    TextField("e.g. Sushi at Mikuni", text: $title)
                    Picker("Vibe", selection: $category) {
                        ForEach(DateNightCategory.allCases, id: \.self) { c in
                            Text(c.rawValue).tag(c.rawValue)
                        }
                    }
                }

                // MARK: Destinations / stops
                Section {
                    ForEach(destinations.indices, id: \.self) { idx in
                        HStack(spacing: 10) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(destinations[idx].name).font(.subheadline)
                                if let addr = destinations[idx].address, !addr.isEmpty {
                                    Text(addr)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            if let mapsURL = destinations[idx].mapsURL,
                               let url = URL(string: mapsURL) {
                                Link(destination: url) {
                                    Image(systemName: "map.fill")
                                        .foregroundStyle(.blue)
                                }
                                .buttonStyle(.plain)
                            }
                            // Inline remove — swipeActions are blocked by editMode
                            Button {
                                destinations.remove(at: idx)
                            } label: {
                                Image(systemName: "minus.circle.fill")
                                    .foregroundStyle(.red)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .onMove { from, to in destinations.move(fromOffsets: from, toOffset: to) }

                    Button {
                        addingLocation = true
                    } label: {
                        Label("Add Stop", systemImage: "plus.circle")
                    }
                } header: {
                    Text("Stops / Locations")
                } footer: {
                    if destinations.isEmpty {
                        Text("Search for a restaurant, venue, or area.")
                    }
                }

                Section("Cost / Notes") {
                    TextField("Estimated cost (optional)", text: $estCost).keyboardType(.decimalPad)
                    TextField("Notes", text: $notes, axis: .vertical).lineLimit(2...5)
                }
                Section("Schedule") {
                    Toggle("Schedule this date", isOn: $hasSchedule)
                    if hasSchedule {
                        DatePicker("When", selection: $scheduledAt)
                    }
                }
                if hasSchedule && scheduledAt < Date() {
                    Section("Review") {
                        Stepper(value: $rating, in: 0...5) {
                            HStack {
                                Text("Rating")
                                Spacer()
                                HStack(spacing: 1) {
                                    ForEach(1..<6) { i in
                                        Image(systemName: i <= rating ? "star.fill" : "star")
                                    }
                                }
                                .foregroundStyle(.orange)
                            }
                        }
                        TextField("How was it?", text: $reviewNotes, axis: .vertical)
                            .lineLimit(2...5)
                    }
                }
                if existing != nil {
                    Section {
                        Button("Delete", role: .destructive) {
                            if let existing {
                                Task { await dates.delete(existing); dismiss() }
                            }
                        }
                    }
                }
            }
            .navigationTitle(existing == nil ? "New Date" : "Edit Date")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await save() }
                    } label: {
                        if isSaving { ProgressView() } else { Text("Save") }
                    }
                    .disabled(isSaving || title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .environment(\.editMode, .constant(.active))
        }
        .onAppear {
            if let e = existing {
                title    = e.title
                category = e.category ?? DateNightCategory.dinner.rawValue
                if let dests = e.destinations, !dests.isEmpty {
                    destinations = dests
                }
                estCost = e.estCost.map { String($0) } ?? ""
                notes = e.notes ?? ""
                if let s = e.scheduledAt { hasSchedule = true; scheduledAt = s }
                rating = e.rating ?? 0
                reviewNotes = e.reviewNotes ?? ""
            }
        }
        .sheet(isPresented: $addingLocation) {
            LocationSearchSheet { result in
                destinations.append(DateNightDestination(
                    name: result.name,
                    address: result.address.isEmpty ? nil : result.address,
                    mapsURL: result.mapsURL
                ))
                // Auto-save to the shared family Places library so it shows up
                // in the location pickers and can be reused across dates/trips.
                if let familyID = family.familyID {
                    Task {
                        await trips.saveIfNew(
                            familyID: familyID,
                            name: result.name,
                            address: result.address,
                            mapsURL: result.mapsURL
                        )
                    }
                }
            }
        }
    }

    private func save() async {
        guard let familyID = family.familyID else { return }
        isSaving = true
        let d = DateNight(
            id: existing?.id ?? UUID(),
            familyID: familyID,
            title: title.trimmingCharacters(in: .whitespaces),
            category: category,
            destinations: destinations.isEmpty ? nil : destinations,
            estCost: Double(estCost),
            notes: notes.isEmpty ? nil : notes,
            ideaOnly: !hasSchedule,
            scheduledAt: hasSchedule ? scheduledAt : nil,
            rating: rating == 0 ? nil : rating,
            reviewNotes: reviewNotes.isEmpty ? nil : reviewNotes,
            photoURL: existing?.photoURL,
            movieID: existing?.movieID,
            createdBy: existing?.createdBy ?? family.currentMember?.userID,
            createdAt: existing?.createdAt ?? Date(),
            updatedAt: Date()
        )
        let ok = await dates.save(d)
        isSaving = false
        if ok { dismiss() }
    }
}
