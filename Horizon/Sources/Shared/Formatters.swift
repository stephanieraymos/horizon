import Foundation

enum TripFormat {
    /// "Mar 4 – 8, 2026", "Aug 4 – Sep 2, 2023", or "Mar 4, 2026" for a single day.
    static func dateRange(_ depart: Date?, _ ret: Date?) -> String {
        guard let depart else { return "No dates yet" }
        let cal = Calendar.current
        guard let ret, cal.startOfDay(for: ret) != cal.startOfDay(for: depart) else {
            return depart.formatted(.dateTime.month(.abbreviated).day().year())
        }
        let sameYear = cal.component(.year, from: depart) == cal.component(.year, from: ret)
        let sameMonth = sameYear && cal.component(.month, from: depart) == cal.component(.month, from: ret)
        if sameMonth {
            // e.g. "Oct 1 – 4, 2026". Note: formatting a Date with only .day().year()
            // (no month) renders as a garbled "2026 (day: 4)", so build the end from
            // components instead.
            let start = depart.formatted(.dateTime.month(.abbreviated).day())
            let endDay = cal.component(.day, from: ret)
            let year = cal.component(.year, from: ret)
            return "\(start) – \(endDay), \(year)"
        } else if sameYear {
            let start = depart.formatted(.dateTime.month(.abbreviated).day())
            let end = ret.formatted(.dateTime.month(.abbreviated).day().year())
            return "\(start) – \(end)"
        } else {
            let start = depart.formatted(.dateTime.month(.abbreviated).day().year())
            let end = ret.formatted(.dateTime.month(.abbreviated).day().year())
            return "\(start) – \(end)"
        }
    }

    static func money(_ amount: Double?) -> String? {
        guard let amount else { return nil }
        return amount.formatted(.currency(code: "USD").precision(.fractionLength(0)))
    }
}
