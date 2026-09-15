import SwiftUI

/// One thing counting down, whatever it is: a trip, a party or dinner, a pure
/// countdown (an anniversary, a holiday, a race), or a birthday from People.
///
/// Horizon keeps these in two tables — plans in `fam_trips`, countdowns in
/// `fam_events` — and used to show them two different ways on two screens, with
/// every dated trip ALSO appearing a second time through the `fam_events` row
/// `EventsStore.syncCountdown` writes for it. This is the one shape the Countdowns
/// screen, Home and the reminders all read, built fresh from the stores each time.
struct Countdown: Identifiable {
    enum Source {
        /// A dated plan — a trip, party, dinner, gathering or celebration.
        case plan(Trip)
        /// A standalone countdown row (`fam_events` with no trip).
        case countdown(FamilyEvent)
        /// A birthday synthesized from a person in People — it has no row of its own.
        case birthday(FamilyEvent)
    }

    /// The Countdowns screen's filter. "Countdowns" are the things you only count
    /// down to; Trips and Events are the things you plan.
    enum Category: String, CaseIterable, Identifiable {
        case countdowns = "Countdowns", trips = "Trips", events = "Events"
        var id: String { rawValue }
    }

    let id: String
    let source: Source
    let title: String
    /// Next occurrence (annual countdowns) or the day a plan starts.
    let date: Date
    let emoji: String?
    let systemImage: String
    let tint: Color
    /// "Turns 34", "12th anniversary", "Maui · 7 nights", "Party · Backyard".
    let detail: String?
    /// One word for what it is: "Trip", "Party", "Birthday", "Anniversary", "Countdown".
    let badge: String
    let category: Category
    /// Whole days from today to `date`. Negative only while a plan is under way.
    let daysAway: Int
    /// A plan that has started and not yet ended.
    let isHappeningNow: Bool
    /// Days until a happening plan ends ("3 days left").
    let daysUntilEnd: Int?
    /// Exact local time ("19:30:00") when one is set; nil = all day.
    var time: String? = nil
    /// Photo for the card (a plan's cover, or a countdown's own) and its framing.
    var cover: String? = nil
    var coverFocus: UnitPoint = .center

    /// The exact moment it lands: `date` at `time`, else the start of that day.
    var moment: Date { TimeOfDay.moment(on: date, time: time) }

    /// A birthday synthesized from People — no row to put a time or note on.
    var isFromPeople: Bool {
        if case .birthday = source { return true }
        return false
    }

    var trip: Trip? {
        if case .plan(let t) = source { return t }
        return nil
    }

    var event: FamilyEvent? {
        switch source {
        case .countdown(let e), .birthday(let e): return e
        case .plan: return nil
        }
    }
}

// MARK: - Building

enum CountdownBuilder {
    /// Everything counting down from today, soonest first (plans under way lead).
    ///
    /// - Trip-linked `fam_events` rows are left out: the plan itself is the
    ///   countdown, and showing both is the duplicate the old Events board had.
    ///   The rows stay in the table because Solstice's calendar overlay reads them.
    /// - A People birthday is dropped when a real row already covers it (same
    ///   title, same month/day) — the rule the board used.
    static func build(trips: [Trip], events: [FamilyEvent], birthdays: [FamilyEvent],
                      destinationName: (Trip) -> String? = { $0.destination?.nilIfBlank },
                      showBirthdays: Bool = true, showHolidays: Bool = true,
                      today: Date = Date()) -> [Countdown] {
        let cal = Calendar.current
        let start = cal.startOfDay(for: today)
        func days(to d: Date) -> Int {
            cal.dateComponents([.day], from: start, to: cal.startOfDay(for: d)).day ?? 0
        }

        var out: [Countdown] = []

        // Plans: every dated, non-archived plan that hasn't ended.
        for t in trips where !t.archived && !t.isSomeday && !t.isPast {
            guard let depart = t.departDate else { continue }
            let d = days(to: depart)
            let end = t.returnDate.map { days(to: $0) }
            var parts: [String] = []
            // Length before place: a long place name ("Discovery Park") truncated
            // the row and hid "4 days", the part that says what kind of plan it is.
            if !t.kind.isTravel { parts.append(t.kind.label) }
            if let length = t.lengthLabel { parts.append(length) }
            if let place = destinationName(t) { parts.append(place) }
            out.append(Countdown(
                id: "plan-\(t.id.uuidString)", source: .plan(t), title: t.name, date: depart,
                emoji: nil, systemImage: t.kind.systemImage,
                tint: t.kind.isTravel ? Theme.Colors.brand : .orange,
                detail: parts.isEmpty ? nil : parts.joined(separator: " · "),
                badge: t.kind.label,
                category: t.kind.isTravel ? .trips : .events,
                daysAway: d, isHappeningNow: d < 0, daysUntilEnd: d < 0 ? end : nil,
                time: t.startTime, cover: t.coverPhotoURL?.nilIfBlank,
                coverFocus: UnitPoint(x: t.coverFocusX, y: t.coverFocusY)))
        }

        func passes(_ e: FamilyEvent) -> Bool {
            if e.eventType == FamilyEventType.birthday.rawValue { return showBirthdays }
            if e.eventType == FamilyEventType.holiday.rawValue { return showHolidays }
            return true
        }
        func isUpcoming(_ e: FamilyEvent) -> Bool {
            e.isAnnual || cal.startOfDay(for: e.eventDate) >= start
        }
        func make(_ e: FamilyEvent, source: Countdown.Source, prefix: String) -> Countdown {
            let look = appearance(for: e.eventType)
            return Countdown(
                id: "\(prefix)-\(e.id.uuidString)", source: source, title: e.title,
                date: e.isAnnual ? e.nextOccurrenceDate : e.eventDate,
                emoji: e.emoji?.nilIfBlank, systemImage: look.symbol, tint: look.tint,
                detail: detail(for: e),
                badge: (e.eventType == nil || e.eventType == FamilyEventType.other.rawValue)
                    ? "Countdown" : e.eventType!,
                category: .countdowns,
                daysAway: e.daysAway, isHappeningNow: false, daysUntilEnd: nil,
                time: e.eventTime, cover: e.coverPhotoURL?.nilIfBlank)
        }

        // A trip-linked row is either the copy syncCountdown writes for a plan —
        // never shown, the plan stands in for it — or a countdown a plan was made
        // FROM ("Plan a dinner" on the anniversary), which is hers. That one is
        // hidden only while its plan is listed on the very same day, so it never
        // shows twice and is never lost: once the dinner is over the anniversary
        // is back for next year, and a plan that moves, goes someday or is
        // deleted leaves it standing on its own.
        let planDays = Dictionary(out.compactMap { c in c.trip.map { ($0.id, c.date) } },
                                  uniquingKeysWith: { a, _ in a })
        for e in events where isUpcoming(e) && passes(e) {
            if let tripID = e.tripID {
                if e.isPlanCopy { continue }
                let day = e.isAnnual ? e.nextOccurrenceDate : e.eventDate
                if let d = planDays[tripID], cal.isDate(d, inSameDayAs: day) { continue }
            }
            out.append(make(e, source: .countdown(e), prefix: "event"))
        }

        // People birthdays not already covered by a real row.
        if showBirthdays {
            // Only a real countdown that's still ahead covers a birthday. Counting
            // every row let a plan copy ("Plan a party" from Alex's birthday) or a
            // one-off that has passed hide the birthday every year after.
            let covered = Set(events.filter { !$0.isPlanCopy && isUpcoming($0) }.map(key))
            // A plan made from the birthday ("Plan a party" names it after the
            // birthday, on that day) stands in for it while it's listed — the way
            // a plan made from a real countdown hides that countdown.
            let planned = Set(out.compactMap { c in c.trip == nil ? nil : key(title: c.title, date: c.date) })
            for b in birthdays where !covered.contains(key(b)) && !planned.contains(key(b)) {
                out.append(make(b, source: .birthday(b), prefix: "birthday"))
            }
        }

        return out.sorted { a, b in
            if a.isHappeningNow != b.isHappeningNow { return a.isHappeningNow }
            // The exact moment, so an 8 AM breakfast sorts above a 6 PM dinner.
            if a.moment != b.moment { return a.moment < b.moment }
            return a.title.localizedCaseInsensitiveCompare(b.title) == .orderedAscending
        }
    }

    /// Same title, same month and day — how a real row "covers" a People birthday.
    private static func key(_ e: FamilyEvent) -> String { key(title: e.title, date: e.eventDate) }

    private static func key(title: String, date: Date) -> String {
        let c = Calendar.current.dateComponents([.month, .day], from: date)
        return "\(title.lowercased())|\(c.month ?? 0)-\(c.day ?? 0)"
    }

    static func detail(for e: FamilyEvent) -> String? {
        if let years = e.yearsAtNextOccurrence {
            if e.eventType == FamilyEventType.birthday.rawValue { return "Turns \(years)" }
            if e.eventType == FamilyEventType.anniversary.rawValue { return "\(ordinal(years)) anniversary" }
        }
        guard let type = e.eventType, type != FamilyEventType.other.rawValue,
              type != FamilyEventType.birthday.rawValue,
              type != FamilyEventType.anniversary.rawValue else { return nil }
        return type
    }

    static func appearance(for eventType: String?) -> (symbol: String, tint: Color) {
        switch eventType {
        case FamilyEventType.birthday.rawValue:    return ("birthday.cake.fill", .pink)
        case FamilyEventType.anniversary.rawValue: return ("heart.fill", .purple)
        case FamilyEventType.holiday.rawValue:     return ("star.fill", .orange)
        case FamilyEventType.milestone.rawValue:   return ("flag.fill", .indigo)
        case FamilyEventType.vacation.rawValue:    return ("airplane", Theme.Colors.brand)
        case FamilyEventType.outing.rawValue:      return ("figure.walk", .green)
        case FamilyEventType.school.rawValue:      return ("graduationcap.fill", .blue)
        default:                                   return ("hourglass", .teal)
        }
    }

    /// 1st, 2nd, 3rd, 4th, 11th, 12th, 13th, 21st…
    static func ordinal(_ n: Int) -> String {
        let suffix: String
        switch n % 100 {
        case 11, 12, 13: suffix = "th"
        default:
            switch n % 10 {
            case 1: suffix = "st"
            case 2: suffix = "nd"
            case 3: suffix = "rd"
            default: suffix = "th"
            }
        }
        return "\(n)\(suffix)"
    }
}
