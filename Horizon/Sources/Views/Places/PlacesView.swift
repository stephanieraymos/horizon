import SwiftUI

struct PlacesView: View {
    @Environment(TripsStore.self) private var trips
    @Environment(FamilyStore.self) private var family
    @State private var newPlace: Place?

    private var byCategory: [(cat: String, items: [Place])] {
        Dictionary(grouping: trips.places, by: { $0.category?.nilIfBlank ?? "Other" })
            .map { (cat: $0.key, items: $0.value.sorted { $0.name < $1.name }) }
            .sorted { $0.cat < $1.cat }
    }

    var body: some View {
        List {
            if trips.places.isEmpty {
                ContentUnavailableView("No places yet", systemImage: "mappin.and.ellipse",
                    description: Text("Places you save on trips show up here."))
            } else {
                ForEach(byCategory, id: \.cat) { group in
                    Section(group.cat) {
                        ForEach(group.items) { place in
                            NavigationLink { PlaceDetailView(place: place) } label: {
                                HStack {
                                    Image(systemName: place.visited ? "checkmark.circle.fill" : "mappin.and.ellipse")
                                        .foregroundStyle(place.visited ? Theme.Colors.brand : .secondary)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(place.name)
                                        if let a = place.address?.nilIfBlank {
                                            Text(a).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Places")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { if let fid = family.familyID { newPlace = Place(familyID: fid, name: "") } } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(item: $newPlace) { PlaceDetailView(place: $0, isNew: true) }
    }
}

struct PlaceDetailView: View {
    let place: Place
    var isNew: Bool = false
    @Environment(TripsStore.self) private var trips
    @Environment(FamilyStore.self) private var family
    @Environment(\.dismiss) private var dismiss

    @State private var draft: Place
    @State private var planTrip: Trip?

    init(place: Place, isNew: Bool = false) {
        self.place = place; self.isNew = isNew
        _draft = State(initialValue: place)
    }

    var body: some View {
        Form {
            Section {
                TextField("Name", text: $draft.name)
                TextField("Category", text: Binding(get: { draft.category ?? "" }, set: { draft.category = $0.nilIfBlank }))
                TextField("Address", text: Binding(get: { draft.address ?? "" }, set: { draft.address = $0.nilIfBlank }), axis: .vertical)
                TextField("Maps URL", text: Binding(get: { draft.mapsURL ?? "" }, set: { draft.mapsURL = $0.nilIfBlank }))
                Toggle("Visited", isOn: $draft.visited)
            }
            Section("Notes") {
                TextField("Notes", text: Binding(get: { draft.notes ?? "" }, set: { draft.notes = $0.nilIfBlank }), axis: .vertical)
                    .lineLimit(2...6)
            }

            if !isNew {
                let related = trips.trips(referencingPlace: draft.name)
                if !related.isEmpty {
                    Section("Trips here") {
                        ForEach(related) { trip in
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
                    Button("Plan a trip here", systemImage: "airplane.departure") {
                        if let fid = family.familyID {
                            planTrip = Trip(familyID: fid, name: draft.name, destination: draft.name)
                        }
                    }
                }
            }
        }
        .navigationTitle(isNew ? "New Place" : draft.name)
        #if !targetEnvironment(macCatalyst)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            if isNew {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await trips.savePlace(draft); dismiss() } }
                        .disabled(draft.name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .onDisappear { if !isNew, draft != place { Task { await trips.savePlace(draft) } } }
        .sheet(item: $planTrip) { TripEditView(trip: $0) }
    }
}
