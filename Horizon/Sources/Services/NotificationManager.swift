import Foundation
import UserNotifications

/// Schedules local reminders for trips, reservations, and dates. Strategy:
/// clear all pending Horizon notifications and re-schedule from the current
/// (future-dated) data on each sync — simple and always consistent.
enum NotificationManager {
    private static var center: UNUserNotificationCenter { .current() }

    /// Requests authorization if it hasn't been decided yet. Returns whether
    /// notifications are authorized.
    @discardableResult
    static func requestAuthorizationIfNeeded() async -> Bool {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .notDetermined:
            return (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        case .authorized, .provisional, .ephemeral:
            return true
        default:
            return false
        }
    }

    /// Rebuilds all scheduled reminders from current data. Pass `enabled: false`
    /// to just clear everything.
    static func sync(trips: [Trip], reservations: [Reservation], dates: [DateNight], enabled: Bool) async {
        center.removeAllPendingNotificationRequests()
        guard enabled, await requestAuthorizationIfNeeded() else { return }

        let cal = Calendar.current
        let now = Date()

        // Trips: "start packing" 3 days before departure at 9am.
        for trip in trips {
            guard let depart = trip.departDate else { continue }
            guard let fire = cal.date(byAdding: .day, value: -3, to: cal.startOfDay(for: depart)),
                  let at9 = cal.date(bySettingHour: 9, minute: 0, second: 0, of: fire),
                  at9 > now else { continue }
            let days = cal.dateComponents([.day], from: cal.startOfDay(for: now), to: cal.startOfDay(for: depart)).day ?? 3
            schedule(id: "trip-\(trip.id.uuidString)",
                     title: "✈️ \(trip.name)",
                     body: "Your trip is in \(days) days — time to start packing!",
                     at: at9)
        }

        // Reservations: the evening before (6pm).
        for res in reservations {
            guard let start = res.startAt else { continue }
            guard let dayBefore = cal.date(byAdding: .day, value: -1, to: start),
                  let at6 = cal.date(bySettingHour: 18, minute: 0, second: 0, of: dayBefore),
                  at6 > now else { continue }
            let title = res.title.isEmpty ? res.type.label : res.title
            schedule(id: "res-\(res.id.uuidString)",
                     title: "Tomorrow: \(title)",
                     body: reservationBody(res, start: start),
                     at: at6)
        }

        // Dates: 3 hours before the scheduled time.
        for date in dates where !date.ideaOnly {
            guard let when = date.scheduledAt,
                  let fire = cal.date(byAdding: .hour, value: -3, to: when),
                  fire > now else { continue }
            var body = "Date time is coming up"
            if let loc = date.primaryLocationName { body = "Tonight at \(loc)" }
            schedule(id: "date-\(date.id.uuidString)",
                     title: "💕 \(date.title)",
                     body: body,
                     at: fire)
        }
    }

    private static func reservationBody(_ res: Reservation, start: Date) -> String {
        let time = start.formatted(date: .omitted, time: .shortened)
        if let conf = res.confirmationNumber?.nilIfBlank {
            return "\(res.type.label) at \(time) · Conf \(conf)"
        }
        return "\(res.type.label) at \(time)"
    }

    private static func schedule(id: String, title: String, body: String, at date: Date) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
    }
}
