import SwiftUI
import PhotosUI

/// Manage destinations: rename, set a cover, mark as bucket-list, see the trips
/// grouped under each, delete.
struct DestinationsView: View {
    @Environment(TripsStore.self) private var trips

    var body: some View {
        List {
            if trips.destinations.isEmpty {
                ContentUnavailableView("No destinations yet", systemImage: "map",
                    description: Text("Destinations group repeat trips (Disneyland, AfterShock…). Add one from a trip's Destination field."))
            } else {
                ForEach(trips.destinations.sorted { $0.name < $1.name }) { dest in
                    NavigationLink {
                        DestinationDetailView(destination: dest)
                    } label: {
                        HStack(spacing: 12) {
                            CoverImage(cover: dest.coverPhotoURL) {
                                RoundedRectangle(cornerRadius: 8).fill(Theme.Colors.brand.opacity(0.15))
                                    .overlay { Image(systemName: "mappin.and.ellipse").foregroundStyle(Theme.Colors.brand) }
                            }
                            .frame(width: 44, height: 44).clipShape(RoundedRectangle(cornerRadius: 8))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(dest.name).font(.headline)
                                Text("\(trips.tripCount(forDestination: dest.id)) trip\(trips.tripCount(forDestination: dest.id) == 1 ? "" : "s")")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            if dest.isWishlist {
                                Spacer(); Image(systemName: "sparkles").foregroundStyle(.purple)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Destinations")
    }
}

private struct DestinationDetailView: View {
    let destination: Destination
    @Environment(TripsStore.self) private var trips
    @Environment(FamilyStore.self) private var family
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var isWishlist: Bool
    @State private var coverItem: PhotosPickerItem?
    @State private var confirmDelete = false

    init(destination: Destination) {
        self.destination = destination
        _name = State(initialValue: destination.name)
        _isWishlist = State(initialValue: destination.isWishlist)
    }

    private var current: Destination { trips.destinations.first { $0.id == destination.id } ?? destination }

    var body: some View {
        Form {
            Section {
                PhotosPicker(selection: $coverItem, matching: .images) {
                    CoverImage(cover: current.coverPhotoURL) {
                        ZStack {
                            Theme.Colors.brand.opacity(0.15)
                            Label("Add cover photo", systemImage: "photo.badge.plus").foregroundStyle(Theme.Colors.brand)
                        }
                    }
                    .frame(height: 150).frame(maxWidth: .infinity).clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .listRowInsets(EdgeInsets())
            }

            Section("Destination") {
                TextField("Name", text: $name)
                Toggle("Bucket-list / someday", isOn: $isWishlist)
            }

            Section("Trips") {
                let list = trips.trips(forDestination: current.id)
                if list.isEmpty {
                    Text("No trips yet.").foregroundStyle(.secondary)
                } else {
                    ForEach(list) { trip in
                        NavigationLink { TripDetailView(trip: trip) } label: {
                            HStack {
                                Text(trip.name)
                                Spacer()
                                Text(TripFormat.dateRange(trip.departDate, trip.returnDate))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }

            Section {
                Button("Delete Destination", role: .destructive) { confirmDelete = true }
            }
        }
        .navigationTitle(current.name)
        #if !targetEnvironment(macCatalyst)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .onChange(of: coverItem) { _, item in
            guard let item, let fid = family.familyID else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self) {
                    await trips.setDestinationCover(id: current.id, familyID: fid, imageData: data)
                }
                coverItem = nil
            }
        }
        .onDisappear {
            if name != destination.name { Task { await trips.renameDestination(current, name: name) } }
            if isWishlist != destination.isWishlist {
                var d = current; d.isWishlist = isWishlist
                Task { await trips.saveDestination(d) }
            }
        }
        .confirmationDialog("Delete this destination?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                Task { await trips.deleteDestination(current); dismiss() }
            }
        } message: {
            Text("Trips keep their name but lose the grouping.")
        }
    }
}
