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

    init(reservation: Reservation) {
        _draft = State(initialValue: reservation)
        _hasStart = State(initialValue: reservation.startAt != nil)
        _hasEnd = State(initialValue: reservation.endAt != nil)
        _startAt = State(initialValue: reservation.startAt ?? Date())
        _endAt = State(initialValue: reservation.endAt ?? reservation.startAt ?? Date())
        _costText = State(initialValue: reservation.costCents.map { String(format: "%.2f", Double($0) / 100) } ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Type", selection: $draft.type) {
                        ForEach(ReservationType.allCases, id: \.self) { t in
                            Label(t.label, systemImage: t.systemImage).tag(t)
                        }
                    }
                    TextField(titlePlaceholder, text: $draft.title)
                    TextField("Confirmation #", text: bind(\.confirmationNumber))
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
                    TextField("Address", text: bind(\.address), axis: .vertical)
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
