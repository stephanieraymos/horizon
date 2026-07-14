import SwiftUI

/// Paste a confirmation email/text and turn it into a prefilled reservation —
/// the type, date, confirmation number, and flight details are inferred, then
/// the reservation editor opens for review. (The in-app half of email import.)
struct PasteReservationSheet: View {
    let familyID: UUID
    let tripID: UUID
    /// Called with the prefilled reservation to open the editor.
    let onParsed: (Reservation) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var text = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextEditor(text: $text)
                        .frame(minHeight: 180)
                        .overlay(alignment: .topLeading) {
                            if text.isEmpty {
                                Text("Paste your confirmation email or booking details here…")
                                    .foregroundStyle(.tertiary).padding(.top, 8).padding(.leading, 5)
                                    .allowsHitTesting(false)
                            }
                        }
                    if UIPasteboard.general.hasStrings {
                        Button("Paste from clipboard", systemImage: "doc.on.clipboard") {
                            text = UIPasteboard.general.string ?? ""
                        }
                    }
                } footer: {
                    Text("Horizon fills in what it recognizes — flight number, dates, confirmation code — and you confirm the rest.")
                }
            }
            .navigationTitle("Paste Confirmation")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Scan") { scan() }
                        .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private func scan() {
        let p = ReservationParser.parse(text)
        var r = Reservation(familyID: familyID, tripID: tripID, type: p.type ?? .other)
        r.confirmationNumber = p.confirmation
        r.startAt = p.startAt
        if let f = p.flightNumber { r.details["flight_number"] = f; r.title = f }
        if let a = p.airline { r.details["airline"] = a }
        if let d = p.departAirport { r.details["depart_airport"] = d }
        if let ar = p.arriveAirport { r.details["arrive_airport"] = ar }
        onParsed(r)
        dismiss()
    }
}
