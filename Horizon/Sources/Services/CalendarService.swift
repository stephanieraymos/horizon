import Foundation
import EventKit

/// Adds trip reservations to the user's Apple Calendar via EventKit. Uses
/// write-only access (iOS 17+), so Horizon never reads existing events.
enum CalendarService {
    enum CalendarError: LocalizedError {
        case accessDenied
        case noDate
        case saveFailed(String)

        var errorDescription: String? {
            switch self {
            case .accessDenied: "Calendar access was denied. Enable it in Settings › Horizon."
            case .noDate: "This reservation has no date to add."
            case .saveFailed(let m): m
            }
        }
    }

    private static func requestAccess(_ store: EKEventStore) async throws {
        let granted: Bool
        if #available(iOS 17.0, macCatalyst 17.0, *) {
            granted = try await store.requestWriteOnlyAccessToEvents()
        } else {
            granted = try await store.requestAccess(to: .event)
        }
        guard granted else { throw CalendarError.accessDenied }
    }

    /// Adds one reservation to the default calendar. Returns nothing on success,
    /// throws a `CalendarError` otherwise.
    static func add(reservation: Reservation, tripName: String?) async throws {
        guard let start = reservation.startAt else { throw CalendarError.noDate }
        let store = EKEventStore()
        try await requestAccess(store)

        let event = EKEvent(eventStore: store)
        event.title = reservation.title.isEmpty ? reservation.type.label : reservation.title
        event.startDate = start
        // Default to a 1-hour block when there's no explicit end.
        event.endDate = reservation.endAt ?? start.addingTimeInterval(3600)
        event.location = reservation.address?.nilIfBlank

        var noteLines: [String] = []
        if let trip = tripName?.nilIfBlank { noteLines.append("Trip: \(trip)") }
        if let conf = reservation.confirmationNumber?.nilIfBlank { noteLines.append("Confirmation: \(conf)") }
        if let maps = reservation.mapsURL?.nilIfBlank { noteLines.append(maps) }
        event.notes = noteLines.isEmpty ? nil : noteLines.joined(separator: "\n")

        event.calendar = store.defaultCalendarForNewEvents
        do {
            try store.save(event, span: .thisEvent)
        } catch {
            throw CalendarError.saveFailed(error.localizedDescription)
        }
    }
}
