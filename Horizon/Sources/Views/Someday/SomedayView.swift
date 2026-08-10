import SwiftUI

/// The bucket-list layer: dateless "someday" trips + wishlist destinations.
/// Each converts toward a real plan — a someday trip gets dates, a wishlist
/// destination spins up a trip in one tap.
struct SomedayView: View {
    @Environment(TripsStore.self) private var trips
    @Environment(FamilyStore.self) private var family
    @State private var showAddWishlist = false
    @State private var planTripFor: Destination?
    @State private var newSomedayTrip = false

    // Bare root — AppShell owns this tab's NavigationStack.
    var body: some View {
        Group {
            // Before the first load finishes, "Nothing on the list yet" is a lie —
            // tab order is user-customizable, so Someday can be the first tab shown
            // and TripsStore may not have loaded at all yet.
            if !trips.hasLoaded && trips.somedayTrips.isEmpty && trips.wishlistDestinations.isEmpty {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if trips.somedayTrips.isEmpty && trips.wishlistDestinations.isEmpty {
                    ContentUnavailableView {
                        Label("Nothing on the list yet", systemImage: "map")
                    } description: {
                        Text("Add a someday trip or a wishlist destination you'd love to visit.")
                    } actions: {
                        Button("Add someday trip") { newSomedayTrip = true }
                            .buttonStyle(.borderedProminent)
                        Button("Add wishlist place") { showAddWishlist = true }
                    }
                } else {
                    List {
                        if !trips.somedayTrips.isEmpty {
                            Section("Someday trips") {
                                ForEach(trips.somedayTrips) { TripRow(trip: $0) }
                            }
                        }
                        Section("Wishlist destinations") {
                            ForEach(trips.wishlistDestinations) { dest in
                                WishlistRow(destination: dest) { planTripFor = dest }
                            }
                            .onDelete(perform: deleteWishlist)
                            if trips.wishlistDestinations.isEmpty {
                                Button("Add a wishlist place") { showAddWishlist = true }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Someday")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button("Someday trip", systemImage: "airplane") { newSomedayTrip = true }
                        Button("Wishlist place", systemImage: "mappin") { showAddWishlist = true }
                    } label: { Image(systemName: "plus") }
                }
            }
            // This tab never loaded its own data — it relied on Home/Events being
            // visited first. Opening Someday first showed an empty bucket list.
            .task { if !trips.hasLoaded { await trips.load() } }
            .refreshable { await trips.load() }
            .sheet(isPresented: $showAddWishlist) {
                if let familyID = family.familyID {
                    WishlistDestinationEditView(destination: Destination(familyID: familyID, name: "", isWishlist: true))
                }
            }
            .sheet(isPresented: $newSomedayTrip) {
                if let familyID = family.familyID {
                    // A someday trip is just a trip with no dates.
                    TripEditView(trip: Trip(familyID: familyID, name: ""))
                }
            }
            .sheet(item: $planTripFor) { dest in
                if let familyID = family.familyID {
                    TripEditView(trip: Trip(familyID: familyID, name: dest.name,
                                            destination: dest.name, destinationID: dest.id))
                }
            }
    }

    private func deleteWishlist(_ offsets: IndexSet) {
        let items = offsets.map { trips.wishlistDestinations[$0] }
        Task { for item in items { await trips.deleteDestination(item) } }
    }
}

private struct WishlistRow: View {
    let destination: Destination
    let onPlan: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(destination.name).font(.headline)
                if let kind = destination.kind?.nilIfBlank {
                    Text(kind).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button("Plan", systemImage: "airplane.departure", action: onPlan)
                .labelStyle(.titleOnly)
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
    }
}

private struct WishlistDestinationEditView: View {
    @Environment(TripsStore.self) private var trips
    @Environment(\.dismiss) private var dismiss
    @State private var draft: Destination

    init(destination: Destination) { _draft = State(initialValue: destination) }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Place name", text: $draft.name)
                TextField("Kind (beach, city, park…)", text: Binding(
                    get: { draft.kind ?? "" }, set: { draft.kind = $0.nilIfBlank }
                ))
                TextField("Notes", text: Binding(
                    get: { draft.notes ?? "" }, set: { draft.notes = $0.nilIfBlank }
                ), axis: .vertical)
            }
            .navigationTitle("Wishlist Place")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        draft.isWishlist = true
                        Task { await trips.saveDestination(draft); dismiss() }
                    }
                    .disabled(draft.name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}
