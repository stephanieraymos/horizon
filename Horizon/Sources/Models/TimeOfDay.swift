import Foundation

/// A Postgres `time` column (`fam_events.event_time`, `fam_trips.start_time`):
/// a local wall-clock time with no date and no zone, sent and received as
/// "HH:mm:ss". NULL means "all day", and every countdown made before
/// 2026-09-14 is one — so a missing time counts down to the start of the day,
/// exactly as the day-based rows always have.
enum TimeOfDay {
    /// "19:30:00" / "19:30" → hour and minute. Nil for nil, blank or garbage.
    static func components(_ raw: String?) -> DateComponents? {
        guard let raw = raw?.trimmingCharacters(in: .whitespaces), !raw.isEmpty else { return nil }
        let parts = raw.split(separator: ":")
        guard parts.count >= 2, let h = Int(parts[0]), let m = Int(parts[1]),
              (0..<24).contains(h), (0..<60).contains(m) else { return nil }
        return DateComponents(hour: h, minute: m)
    }

    /// The column value for a picked time — seconds always zero.
    static func string(from date: Date) -> String {
        let c = Calendar.current.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d:00", c.hour ?? 0, c.minute ?? 0)
    }

    /// `day` at the stored time, or the start of `day` when there's no time.
    /// Built from components, never `Calendar.date(bySetting:)`, which searches
    /// forward and silently lands on the wrong day.
    static func moment(on day: Date, time raw: String?) -> Date {
        let cal = Calendar.current
        var c = cal.dateComponents([.year, .month, .day], from: day)
        let t = components(raw)
        c.hour = t?.hour ?? 0
        c.minute = t?.minute ?? 0
        c.second = 0
        return cal.date(from: c) ?? cal.startOfDay(for: day)
    }

    /// A day with no clock change anywhere, so a stored 02:30 never becomes
    /// 03:30 just because the editor was opened on a spring-forward day.
    private static let referenceDay: Date =
        Calendar.current.date(from: DateComponents(year: 2001, month: 1, day: 1, hour: 12)) ?? Date()

    /// A picker seed: the stored time (or 7 PM) on the reference day — only the
    /// hour and minute are ever read back.
    static func pickerDate(_ raw: String?) -> Date {
        let cal = Calendar.current
        var c = cal.dateComponents([.year, .month, .day], from: referenceDay)
        let t = components(raw)
        c.hour = t?.hour ?? 19
        c.minute = t?.minute ?? 0
        return cal.date(from: c) ?? Date()
    }

    /// "7:30 PM" in the viewer's locale.
    static func label(_ raw: String?) -> String? {
        guard components(raw) != nil else { return nil }
        return moment(on: referenceDay, time: raw).formatted(date: .omitted, time: .shortened)
    }
}
