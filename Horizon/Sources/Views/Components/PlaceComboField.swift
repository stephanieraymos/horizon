import SwiftUI

/// Location combobox backed by `fam_places`: search existing places, or add a new
/// one inline. Sets the bound text (location/address) and links `placeID`.
struct PlaceComboField: View {
    let placeholder: String
    @Binding var text: String
    @Binding var placeID: UUID?

    @Environment(TripsStore.self) private var trips
    @Environment(FamilyStore.self) private var family

    var body: some View {
        ComboField(
            placeholder: placeholder,
            text: $text,
            options: trips.places.sorted { $0.name < $1.name }.map {
                .init(id: $0.id.uuidString, name: $0.name, icon: "mappin.and.ellipse", subtitle: $0.address)
            },
            pickIcon: "mappin.and.ellipse",
            onPick: { opt in placeID = UUID(uuidString: opt.id) },
            onAdd: { name in
                guard let fid = family.familyID else { return }
                Task { if let p = await trips.createPlace(familyID: fid, name: name) { placeID = p.id } }
            })
    }
}
