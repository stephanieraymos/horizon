import SwiftUI

struct TripsListView: View {
    @Environment(TripsStore.self) private var trips
    @Environment(FamilyStore.self) private var family
    @State private var showNewTrip = false
    @State private var search = ""
    @State private var statusFilter: TripStatus?

    private func matches(_ t: Trip) -> Bool {
        let s = search.trimmingCharacters(in: .whitespaces).lowercased()
        let textOK = s.isEmpty
            || t.name.lowercased().contains(s)
            || (t.destination?.lowercased().contains(s) ?? false)
            || (t.departDate.map { Trip.yearFormatter.string(from: $0).contains(s) } ?? false)
        let statusOK = statusFilter == nil || t.status == statusFilter
        return textOK && statusOK
    }

    private var upcoming: [Trip] { trips.upcoming.filter(matches) }
    private var past: [Trip] { trips.past.filter(matches) }

    var body: some View {
        NavigationStack {
            Group {
                if trips.trips.isEmpty && !trips.isLoading {
                    ContentUnavailableView {
                        Label("No trips yet", systemImage: "airplane")
                    } description: {
                        Text("Plan your first trip, or add a someday idea in the Someday tab.")
                    } actions: {
                        Button("New Trip") { showNewTrip = true }
                            .buttonStyle(.borderedProminent)
                    }
                } else if upcoming.isEmpty && past.isEmpty {
                    if !search.isEmpty || statusFilter != nil {
                        ContentUnavailableView.search
                    } else {
                        ContentUnavailableView("All your trips are Someday", systemImage: "map",
                            description: Text("Dated trips show here; check the Someday tab for undated ideas."))
                    }
                } else {
                    List {
                        if !upcoming.isEmpty {
                            Section("Upcoming") { ForEach(upcoming) { TripRow(trip: $0) } }
                        }
                        if !past.isEmpty {
                            Section("Past") { ForEach(past) { TripRow(trip: $0) } }
                        }
                    }
                }
            }
            .navigationTitle("Trips")
            .searchable(text: $search, prompt: "Search trips")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    NavigationLink { DestinationsView() } label: { Image(systemName: "map") }
                }
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
                ToolbarItem(placement: .primaryAction) {
                    Button { showNewTrip = true } label: { Image(systemName: "plus") }
                }
            }
            .refreshable { await trips.load() }
            .sheet(isPresented: $showNewTrip) {
                if let familyID = family.familyID {
                    TripEditView(trip: Trip(familyID: familyID, name: ""))
                } else {
                    Text("Loading your family…").padding()
                }
            }
        }
    }
}

struct TripRow: View {
    let trip: Trip
    @Environment(TripsStore.self) private var trips

    var body: some View {
        NavigationLink {
            TripDetailView(trip: trip)
        } label: {
            HStack(spacing: 12) {
                if trip.coverPhotoURL?.nilIfBlank != nil {
                    CoverImage(cover: trip.coverPhotoURL) { Color.secondary.opacity(0.12) }
                        .frame(width: 46, height: 46)
                        .clipShape(RoundedRectangle(cornerRadius: 9))
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(trip.name).font(.headline)
                    if let subtitle = subtitle {
                        Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
                    }
                    Text(TripFormat.dateRange(trip.departDate, trip.returnDate))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                CountdownBadge(trip: trip)
            }
            .padding(.vertical, 2)
        }
    }

    private var subtitle: String? {
        trips.destination(for: trip)?.name ?? trip.destination?.nilIfBlank
    }
}

struct CountdownBadge: View {
    let trip: Trip

    var body: some View {
        let text = trip.countdownText
        if !text.isEmpty {
            Text(text)
                .font(.caption).fontWeight(.semibold)
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(tint.opacity(0.15), in: Capsule())
                .foregroundStyle(tint)
        }
    }

    private var tint: Color {
        if trip.isSomeday { return .purple }
        if trip.countdownText == "Now" { return .green }
        if trip.isPast { return .secondary }
        return Theme.Colors.brand
    }
}
