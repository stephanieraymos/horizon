import SwiftUI

struct ReservationEditView: View {
    @Environment(TripDetailStore.self) private var detail
    @Environment(\.dismiss) private var dismiss

    @State private var draft: Reservation
    @State private var hasStart: Bool
    @State private var hasEnd: Bool
    @State private var startAt: Date
    @State private var endAt: Date
    @State private var costText: String
    @State private var typeText: String
    @State private var pasteText: String = ""

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

                Section("Location") {
                    PlaceComboField(placeholder: "Address / place", text: bind(\.address), placeID: $draft.placeID)
                    TextField("Maps URL", text: bind(\.mapsURL))
                }

                Section("Cost & notes") {
                    TextField("Cost (USD)", text: $costText)
                        #if !targetEnvironment(macCatalyst)
                        .keyboardType(.decimalPad)
                        #endif
                    TextField("Notes", text: bind(\.notes), axis: .vertical)
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
        if p.flightNumber != nil, draft.type == .other {
            draft.type = .flight; typeText = ReservationType.flight.label
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
