import SwiftUI

struct TripsListView: View {
    @Environment(TripsStore.self) private var trips
    @Environment(FamilyStore.self) private var family
    @State private var showNewTrip = false

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
                } else {
                    List {
                        if !trips.upcoming.isEmpty {
                            Section("Upcoming") {
                                ForEach(trips.upcoming) { TripRow(trip: $0) }
                            }
                        }
                        if !trips.past.isEmpty {
                            Section("Past") {
                                ForEach(trips.past) { TripRow(trip: $0) }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Trips")
            .toolbar {
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
