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
            List {
                if !dates.upcoming.isEmpty {
                    Section(header: upcomingHeader) {
                        ForEach(dates.upcoming) { d in row(for: d) }
                    }
                }
                if !dates.ideas.isEmpty {
                    Section("Ideas") {
                        ForEach(dates.ideas) { d in row(for: d) }
                    }
                }
                if !dates.past.isEmpty {
                    Section("Past") {
                        ForEach(dates.past) { d in row(for: d) }
                    }
                }
                if dates.dates.isEmpty {
                    ContentUnavailableView(
                        "No dates yet",
                        systemImage: "heart",
                        description: Text("Save ideas for dates, then schedule them when you're ready.")
                    )
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Dates")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { creating = true } label: { Image(systemName: "plus") }
                }
            }
            .task { if dates.dates.isEmpty { await dates.load() } }
            .refreshable { await dates.load() }
            .sheet(item: $editing) { DateNightEditView(existing: $0) }
            .sheet(isPresented: $creating) { DateNightEditView(existing: nil) }
        }
    }

    @ViewBuilder
    private var upcomingHeader: some View {
        if let next = dates.upcoming.first, let when = next.scheduledAt {
            let cal = Calendar.current
            let days = cal.dateComponents([.day], from: cal.startOfDay(for: Date()), to: cal.startOfDay(for: when)).day ?? 0
            if days >= 0 && days <= 30 {
                Text("Upcoming — date in \(days) day\(days == 1 ? "" : "s")")
            } else {
                Text("Upcoming")
            }
        } else {
            Text("Upcoming")
        }
    }

    private func row(for d: DateNight) -> some View {
        Button { editing = d } label: { DateRow(date: d) }
            .buttonStyle(.plain)
            .swipeActions(edge: .trailing) {
                Button(role: .destructive) {
                    Task { await dates.delete(d) }
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
    }
}

private struct DateRow: View {
    let date: DateNight
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 6) {
                Text(date.title).font(.headline).fixedSize(horizontal: false, vertical: true)
                // Chips + location wrap onto multiple lines instead of squishing.
                FlowLayout(spacing: 6) {
                    if let cat = date.category {
                        Text(cat).font(.caption)
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(Color(.tertiarySystemFill), in: Capsule())
                            .foregroundStyle(.secondary)
                    }
                    if let locName = date.primaryLocationName {
                        Label(locName, systemImage: "mappin.and.ellipse")
                            .font(.caption).foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }
                if let dests = date.destinations, dests.count > 1 {
                    Text("\(dests.count) stops").font(.caption2).foregroundStyle(.tertiary)
                }
            }
            Spacer(minLength: 8)
            // Date/time + rating in a clean trailing column.
            VStack(alignment: .trailing, spacing: 3) {
                if let when = date.scheduledAt {
                    Text(dayLabel(when)).font(.caption.weight(.medium)).foregroundStyle(.secondary)
                    Text(timeLabel(when)).font(.caption2).foregroundStyle(.tertiary)
                }
                if let rating = date.rating, date.isPast {
                    HStack(spacing: 1) {
                        ForEach(1..<6) { i in
                            Image(systemName: i <= rating ? "star.fill" : "star").font(.caption2)
                        }
                    }
                    .foregroundStyle(.orange)
                }
            }
            .fixedSize()
        }
        .padding(.vertical, 2)
    }
    private var icon: String {
        if date.ideaOnly { return "lightbulb" }
        if date.isPast { return "clock" }
        return "heart.fill"
    }
    private var color: Color {
        if date.ideaOnly { return .yellow }
        if date.isPast { return .secondary }
        return .pink
    }
    private func dayLabel(_ d: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "MMM d"; return f.string(from: d)
    }
    private func timeLabel(_ d: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "h:mm a"; return f.string(from: d)
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
