import SwiftUI

/// Places to visit on a trip — multiple, each a real map location (address +
/// Apple Maps link) from the shared places library. Hotels are just places with
/// the "Hotel" category.
struct TripPlacesSection: View {
    let store: TripDetailStore
    let familyID: UUID
    @Environment(TripsStore.self) private var trips

    @State private var addingCategory: String?

    /// Resolved (link, place) pairs in trip order.
    private var linked: [(tripPlace: TripPlace, place: Place)] {
        store.tripPlaces
            .sorted { $0.sort < $1.sort }
            .compactMap { tp in trips.places.first(where: { $0.id == tp.placeID }).map { (tp, $0) } }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Places").font(.title3.bold())
                Spacer()
                Menu {
                    ForEach(PlaceCategory.all, id: \.self) { cat in
                        Button(cat, systemImage: iconFor(cat)) { addingCategory = cat }
                    }
                } label: {
                    Image(systemName: "plus.circle.fill").font(.title3)
                }
                .tint(Theme.Colors.brand)
            }

            if linked.isEmpty {
                Text("Add the places you'll visit — hotels, restaurants, sights. Each links to a map location with an address.")
                    .font(.callout).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding().background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 12))
            } else {
                ForEach(linked, id: \.tripPlace.id) { item in
                    HStack(spacing: 12) {
                        Image(systemName: item.place.categoryIcon)
                            .foregroundStyle(Theme.Colors.brand).frame(width: 26)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.place.name).font(.subheadline.weight(.medium))
                            if let addr = item.place.address?.nilIfBlank {
                                Text(addr).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                            if let cat = item.place.category?.nilIfBlank {
                                Text(cat).font(.caption2)
                                    .padding(.horizontal, 6).padding(.vertical, 1)
                                    .background(Color(.tertiarySystemFill), in: Capsule())
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        if let maps = item.place.mapsURL?.nilIfBlank, let url = URL(string: maps) {
                            Link(destination: url) { Image(systemName: "map.fill").foregroundStyle(.blue) }
                                .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                    .contextMenu {
                        Button("Remove", role: .destructive) { Task { await store.unlinkPlace(item.tripPlace) } }
                    }
                }
            }
        }
        .sheet(isPresented: Binding(get: { addingCategory != nil },
                                    set: { if !$0 { addingCategory = nil } })) {
            let category = addingCategory
            LocationSearchSheet { result in
                Task {
                    if let place = await trips.saveIfNew(familyID: familyID, name: result.name,
                                                         address: result.address, mapsURL: result.mapsURL,
                                                         category: category) {
                        await store.linkPlace(placeID: place.id, familyID: familyID)
                    }
                }
            }
        }
    }

    private func iconFor(_ category: String) -> String {
        switch category.lowercased() {
        case "hotel": return "bed.double.fill"
        case "restaurant": return "fork.knife"
        case "attraction": return "star.fill"
        case "beach": return "beach.umbrella.fill"
        case "park": return "figure.hiking"
        case "shopping": return "bag.fill"
        case "airport": return "airplane"
        default: return "mappin.circle.fill"
        }
    }
}
