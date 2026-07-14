import Foundation

/// Best-effort extraction of reservation fields from pasted confirmation text.
/// Conservative: only fills what it can match with reasonable confidence and
/// leaves everything else to manual entry.
enum ReservationParser {
    struct Parsed {
        var confirmation: String?
        var airline: String?
        var flightNumber: String?
        var departAirport: String?
        var arriveAirport: String?
        var startAt: Date?
        /// Best-guess reservation type from keywords (nil if unclear).
        var type: ReservationType?
    }

    /// A single detected booking, ready to become a `Reservation`.
    struct Detected {
        var type: ReservationType
        var title: String?
        var confirmation: String?
        var startAt: Date?
        var endAt: Date?
        var details: [String: String] = [:]
    }

    /// All dates mentioned, in document order (with times when present).
    private static func allDates(in text: String) -> [Date] {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return detector.matches(in: text, range: range).compactMap(\.date)
    }

    /// All flight numbers (airline code + digits) in document order.
    private static func allFlights(in text: String) -> [(airline: String, number: String)] {
        guard let re = try? NSRegularExpression(pattern: #"\b([A-Z]{2})\s?(\d{1,4})\b"#) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return re.matches(in: text, range: range).compactMap { m in
            guard let a = Range(m.range(at: 1), in: text), let n = Range(m.range(at: 2), in: text) else { return nil }
            let code = String(text[a])
            // Skip common non-airline two-letter+digit noise.
            guard !["PM", "AM"].contains(code) else { return nil }
            return (code, "\(code)\(text[n])")
        }
    }

    /// Detects one or more bookings from pasted text — multiple flight legs
    /// (outbound + return), or a hotel stay with check-in/check-out. Falls back
    /// to a single best-guess reservation.
    static func detectAll(_ text: String) -> [Detected] {
        let confirmation = firstMatch(
            #"(?:confirmation|record locator|booking|conf(?:irmation)?\s*(?:#|number|no)?)\s*[:#]?\s*([A-Z0-9]{5,8})"#,
            in: text, group: 1)
        let flights = allFlights(in: text)
        let dates = allDates(in: text)

        // Multi-leg flights: one reservation per flight number, paired with the
        // date and airport pair at the same index where available.
        if !flights.isEmpty {
            let codes = allMatches(#"\b([A-Z]{3})\b"#, in: text)
                .filter { !["THE", "AND", "YOU", "FOR", "PNR", "ETA", "ETD"].contains($0) }
            return flights.enumerated().map { i, flight in
                var d = Detected(type: .flight, title: flight.number, confirmation: confirmation)
                d.startAt = i < dates.count ? dates[i] : dates.first
                d.details["airline"] = flight.airline
                d.details["flight_number"] = flight.number
                if codes.count >= (2 * i + 2) {
                    d.details["depart_airport"] = codes[2 * i]
                    d.details["arrive_airport"] = codes[2 * i + 1]
                }
                return d
            }
        }

        // Hotel: check-in / check-out as the first two dates.
        if inferType(from: text, hasFlight: false) == .lodging {
            var d = Detected(type: .lodging, title: hotelName(in: text), confirmation: confirmation)
            d.startAt = dates.first
            d.endAt = dates.count > 1 ? dates[1] : nil
            return [d]
        }

        // Fallback: a single reservation of the best-guess type.
        let type = inferType(from: text, hasFlight: false) ?? .other
        return [Detected(type: type, title: nil, confirmation: confirmation, startAt: dates.first)]
    }

    /// Best-effort hotel name — a line containing a lodging keyword.
    private static func hotelName(in text: String) -> String? {
        let brands = ["hotel", "inn", "resort", "suites", "lodge", "marriott", "hilton", "hyatt"]
        for raw in text.split(whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            let lower = line.lowercased()
            if brands.contains(where: lower.contains), line.count <= 60, !line.isEmpty {
                return line
            }
        }
        return nil
    }

    private static func firstMatch(_ pattern: String, in text: String, group: Int = 1) -> String? {
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let m = re.firstMatch(in: text, range: range), m.numberOfRanges > group,
              let r = Range(m.range(at: group), in: text) else { return nil }
        return String(text[r]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func allMatches(_ pattern: String, in text: String, group: Int = 1) -> [String] {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return re.matches(in: text, range: range).compactMap { m in
            guard m.numberOfRanges > group, let r = Range(m.range(at: group), in: text) else { return nil }
            return String(text[r])
        }
    }

    static func parse(_ text: String) -> Parsed {
        var p = Parsed()

        // Confirmation / record locator: 5–8 alphanumerics after a keyword.
        p.confirmation = firstMatch(
            #"(?:confirmation|record locator|booking|conf(?:irmation)?\s*(?:#|number|no)?)\s*[:#]?\s*([A-Z0-9]{5,8})"#,
            in: text, group: 1)

        // Flight number: two-letter airline code + 1–4 digits (e.g. "UA 245", "AS1234").
        if let re = try? NSRegularExpression(pattern: #"\b([A-Z]{2})\s?(\d{1,4})\b"#) {
            let range = NSRange(text.startIndex..., in: text)
            if let m = re.firstMatch(in: text, range: range),
               let a = Range(m.range(at: 1), in: text), let n = Range(m.range(at: 2), in: text) {
                p.airline = String(text[a])
                p.flightNumber = "\(text[a])\(text[n])"
            }
        }

        // Airport IATA codes — only trust them when this looks like a flight.
        if p.flightNumber != nil {
            let codes = allMatches(#"\b([A-Z]{3})\b"#, in: text)
                .filter { !["THE", "AND", "YOU", "FOR", "PNR", "ETA", "ETD"].contains($0) }
            if codes.count >= 2 {
                p.departAirport = codes[0]
                p.arriveAirport = codes[1]
            }
        }

        // Date/time — NSDataDetector handles many natural formats robustly.
        p.startAt = firstDate(in: text)

        // Type inference from keywords (flight already implied by a flight number).
        p.type = inferType(from: text, hasFlight: p.flightNumber != nil)

        return p
    }

    /// First date (with time if present) mentioned in the text.
    private static func firstDate(in text: String) -> Date? {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        return detector.firstMatch(in: text, range: range)?.date
    }

    private static func inferType(from text: String, hasFlight: Bool) -> ReservationType? {
        if hasFlight { return .flight }
        let t = text.lowercased()
        func has(_ words: [String]) -> Bool { words.contains { t.contains($0) } }
        if has(["check-in", "check in", "hotel", "nights", "room ", "airbnb", "vrbo", "resort"]) { return .lodging }
        if has(["rental car", "car rental", "pick-up", "pickup location", "hertz", "enterprise", "avis"]) { return .car }
        if has(["table for", "party of", "reservation for", "restaurant", "dining"]) { return .dining }
        if has(["train", "amtrak", "rail", "platform"]) { return .rail }
        if has(["ferry"]) { return .ferry }
        if has(["admission", "ticket", "park hopper", "theme park", "disneyland", "universal"]) { return .themepark }
        if has(["flight", "airline", "boarding", "departure gate"]) { return .flight }
        return nil
    }
}
