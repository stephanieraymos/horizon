import SwiftUI

/// Paste a confirmation email/text and turn it into one or more prefilled
/// reservations — types, dates, confirmation, flight legs, and hotel check-in/
/// out are inferred. A single result opens the editor for review; multiple
/// (e.g. outbound + return flights) are listed to add in one tap.
struct PasteReservationSheet: View {
    let familyID: UUID
    let tripID: UUID
    /// Open the editor for a single detected reservation.
    let onReview: (Reservation) -> Void
    /// Save several detected reservations at once.
    let onImportMany: ([Reservation]) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var detected: [Reservation] = []
    @State private var didScan = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextEditor(text: $text)
                        .frame(minHeight: 160)
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
                            didScan = false
                        }
                    }
                } footer: {
                    Text("Horizon fills in what it recognizes — flight legs, hotel dates, confirmation code — and you confirm the rest.")
                }

                if didScan {
                    if detected.isEmpty {
                        Section { Text("Couldn't detect a booking. Try adding it manually.").foregroundStyle(.secondary) }
                    } else if detected.count > 1 {
                        Section("Detected \(detected.count)") {
                            ForEach(detected) { r in
                                HStack(spacing: 12) {
                                    Image(systemName: r.type.systemImage).foregroundStyle(Theme.Colors.brand).frame(width: 24)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(r.title.isEmpty ? r.type.label : r.title).font(.subheadline.weight(.medium))
                                        if let start = r.startAt {
                                            Text(start, format: .dateTime.month(.abbreviated).day().hour().minute())
                                                .font(.caption).foregroundStyle(.secondary)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Paste Confirmation")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if didScan && detected.count > 1 {
                        Button("Add \(detected.count)") { onImportMany(detected); dismiss() }
                    } else if didScan && detected.count == 1 {
                        Button("Review") { let r = detected[0]; dismiss(); onReview(r) }
                    } else {
                        Button("Scan") { scan() }
                            .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
        }
    }

    private func scan() {
        detected = ReservationParser.detectAll(text).map { d in
            var r = Reservation(familyID: familyID, tripID: tripID, type: d.type)
            r.confirmationNumber = d.confirmation
            r.startAt = d.startAt
            r.endAt = d.endAt
            r.details = d.details
            if let title = d.title { r.title = title }
            return r
        }
        didScan = true
    }
}
