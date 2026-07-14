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
        return p
    }
}
