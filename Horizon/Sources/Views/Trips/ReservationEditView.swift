import SwiftUI
import PhotosUI

struct ReservationEditView: View {
    @Environment(TripDetailStore.self) private var detail
    @Environment(TripsStore.self) private var trips
    @Environment(FamilyStore.self) private var family
    @Environment(\.dismiss) private var dismiss

    @State private var draft: Reservation
    @State private var hasStart: Bool
    @State private var hasEnd: Bool
    @State private var startAt: Date
    @State private var endAt: Date
    @State private var costText: String
    @State private var typeText: String
    @State private var pasteText: String = ""
    @State private var searchingLocation = false
    @State private var screenshotItems: [PhotosPickerItem] = []
    @State private var uploadingShots = false

    /// Screenshots attached to this reservation.
    private var screenshots: [TripDocument] {
        detail.documents.filter { $0.reservationID == draft.id && $0.isImage }
    }

    init(reservation: Reservation) {
        _draft = State(initialValue: reservation)
        _hasStart = State(initialValue: reservation.startAt != nil)
        _hasEnd = State(initialValue: reservation.endAt != nil)
        _startAt = State(initialValue: reservation.startAt ?? Date())
        _endAt = State(initialValue: reservation.endAt ?? reservation.startAt ?? Date())
        _costText = State(initialValue: reservation.costCents.map { String(format: "%.2f", Double($0) / 100) } ?? "")
        _typeText = State(initialValue: reservation.type.label)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ComboField(
                        placeholder: "Type",
                        text: $typeText,
                        options: ReservationType.allCases.map { .init(id: $0.rawValue, name: $0.label, icon: $0.systemImage) },
                        allowAdd: false,
                        onPick: { opt in
                            if let t = ReservationType(rawValue: opt.id) { draft.type = t }
                        })
                    TextField(titlePlaceholder, text: $draft.title)
                    TextField("Confirmation #", text: bind(\.confirmationNumber))
                }

                Section {
                    TextField("Paste a confirmation email/text…", text: $pasteText, axis: .vertical)
                        .lineLimit(2...5)
                    Button("Fill from text", systemImage: "wand.and.stars") { applyParse() }
                        .disabled(pasteText.trimmingCharacters(in: .whitespaces).isEmpty)
                } header: {
                    Text("Auto-fill (beta)")
                } footer: {
                    Text("Pulls out confirmation #, flight number, and airports where it can.")
                }

                Section("When") {
                    Toggle(draft.type.startLabel, isOn: $hasStart.animation())
                    if hasStart {
                        DatePicker(draft.type.startLabel, selection: $startAt)
                    }
                    Toggle(draft.type.endLabel, isOn: $hasEnd.animation())
                    if hasEnd {
                        DatePicker(draft.type.endLabel, selection: $endAt)
                    }
                }

                if !draft.type.detailFields.isEmpty {
                    Section(draft.type.label) {
                        ForEach(draft.type.detailFields, id: \.key) { field in
                            TextField(field.label, text: Binding(
                                get: { draft.details[field.key] ?? "" },
                                set: { draft.details[field.key] = $0.nilIfBlank }
                            ))
                        }
                    }
                }

                Section {
                    Button {
                        searchingLocation = true
                    } label: {
                        Label(draft.type == .lodging ? "Find hotel on map" : "Search on map",
                              systemImage: "mappin.and.ellipse")
                    }
                    PlaceComboField(placeholder: "Address / place", text: bind(\.address), placeID: $draft.placeID)
                    TextField("Maps URL", text: bind(\.mapsURL))
                } header: {
                    Text("Location")
                } footer: {
                    if draft.type == .lodging {
                        Text("Searching the map saves the hotel as a place with its address, and adds it to the trip.")
                    }
                }

                Section("Cost & notes") {
                    TextField("Cost (USD)", text: $costText)
                        #if !targetEnvironment(macCatalyst)
                        .keyboardType(.decimalPad)
                        #endif
                    TextField("Notes", text: bind(\.notes), axis: .vertical)
                }

                Section {
                    if !screenshots.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(screenshots) { doc in
                                    CachedStorageImage(path: doc.storagePath) {
                                        Color(.tertiarySystemFill)
                                    }
                                    .scaledToFill()
                                    .frame(width: 84, height: 84)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                    .contextMenu {
                                        Button("Delete", role: .destructive) { Task { await detail.deleteDocument(doc) } }
                                    }
                                }
                            }
                        }
                    }
                    PhotosPicker(selection: $screenshotItems, matching: .images) {
                        Label(uploadingShots ? "Uploading…" : "Add screenshot", systemImage: "photo.badge.plus")
                    }
                    .disabled(uploadingShots)
                } header: {
                    Text("Confirmation screenshots")
                } footer: {
                    Text("Attach photos of your booking confirmation.")
                }
            }
            .navigationTitle(draft.title.isEmpty ? "New \(draft.type.label)" : "Edit")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await save() } }
                        .disabled(draft.title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .sheet(isPresented: $searchingLocation) {
                LocationSearchSheet { result in
                    draft.address = result.address.nilIfBlank
                    draft.mapsURL = result.mapsURL
                    if draft.title.trimmingCharacters(in: .whitespaces).isEmpty { draft.title = result.name }
                    guard let fid = family.familyID else { return }
                    Task {
                        let category = draft.type == .lodging ? "Hotel" : nil
                        if let place = await trips.saveIfNew(familyID: fid, name: result.name,
                                                             address: result.address, mapsURL: result.mapsURL,
                                                             category: category) {
                            draft.placeID = place.id
                            await detail.linkPlace(placeID: place.id, familyID: fid)
                        }
                    }
                }
            }
            .onChange(of: screenshotItems) { _, items in
                guard !items.isEmpty else { return }
                Task { await uploadScreenshots(items) }
            }
        }
    }

    private func uploadScreenshots(_ items: [PhotosPickerItem]) async {
        guard let fid = family.familyID else { return }
        uploadingShots = true
        defer { uploadingShots = false; screenshotItems = [] }
        // Save the reservation first so the screenshot's reservation_id is valid.
        await detail.saveReservation(draft)
        for item in items {
            guard let data = try? await item.loadTransferable(type: Data.self) else { continue }
            let jpeg = UIImage(data: data)?.jpegData(compressionQuality: 0.85) ?? data
            await detail.addDocument(familyID: fid, data: jpeg, fileName: "confirmation.jpg",
                                     contentType: "image/jpeg", kind: .screenshot,
                                     reservationID: draft.id, createdBy: family.currentMember?.userID)
        }
    }

    private var titlePlaceholder: String {
        switch draft.type {
        case .flight: "Airline / flight name"
        case .lodging: "Hotel / place name"
        case .dining: "Restaurant"
        default: "Name"
        }
    }

    private func applyParse() {
        let p = ReservationParser.parse(pasteText)
        if let c = p.confirmation { draft.confirmationNumber = c }
        if let a = p.airline { draft.details["airline"] = a }
        if let f = p.flightNumber {
            draft.details["flight_number"] = f
            if draft.title.trimmingCharacters(in: .whitespaces).isEmpty { draft.title = f }
        }
        if let d = p.departAirport { draft.details["depart_airport"] = d }
        if let ar = p.arriveAirport { draft.details["arrive_airport"] = ar }
        if let start = p.startAt {
            hasStart = true; startAt = start
        }
        // Adopt an inferred type only when the user hasn't already chosen one.
        if let inferred = p.type, draft.type == .other {
            draft.type = inferred; typeText = inferred.label
        }
    }

    private func bind(_ key: WritableKeyPath<Reservation, String?>) -> Binding<String> {
        Binding(get: { draft[keyPath: key] ?? "" }, set: { draft[keyPath: key] = $0.nilIfBlank })
    }

    private func save() async {
        draft.startAt = hasStart ? startAt : nil
        draft.endAt = hasEnd ? endAt : nil
        let cents = Double(costText.replacingOccurrences(of: ",", with: "")).map { Int(($0 * 100).rounded()) }
        draft.costCents = cents
        await detail.saveReservation(draft)
        dismiss()
    }
}
