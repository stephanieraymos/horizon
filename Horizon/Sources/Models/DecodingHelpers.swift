import Foundation

// MARK: - Date-only decoding
// Postgres DATE columns come back from PostgREST as plain "yyyy-MM-dd" strings.
// We parse them in the device's local timezone so calendar UI matches the user's
// expectation (no UTC-midnight-shifts-to-yesterday surprises).

private let _dateOnlyFormatter: DateFormatter = {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.dateFormat = "yyyy-MM-dd"
    f.timeZone = TimeZone.current
    return f
}()

func decodeDateOnly<K: CodingKey>(
    _ container: KeyedDecodingContainer<K>,
    forKey key: K
) throws -> Date {
    let str = try container.decode(String.self, forKey: key)
    let part = String(str.prefix(10))
    if let d = _dateOnlyFormatter.date(from: part) { return d }
    throw DecodingError.dataCorruptedError(
        forKey: key, in: container,
        debugDescription: "Cannot parse date-only value: \(str)"
    )
}

func decodeDateOnlyIfPresent<K: CodingKey>(
    _ container: KeyedDecodingContainer<K>,
    forKey key: K
) throws -> Date? {
    guard let str = try container.decodeIfPresent(String.self, forKey: key) else { return nil }
    let part = String(str.prefix(10))
    return _dateOnlyFormatter.date(from: part)
}

func encodeDateOnly<K: CodingKey>(
    _ container: inout KeyedEncodingContainer<K>,
    _ date: Date,
    forKey key: K
) throws {
    try container.encode(_dateOnlyFormatter.string(from: date), forKey: key)
}

/// Parse a "yyyy-MM-dd" string into a local-midnight Date (nil if malformed),
/// matching how the app decodes DATE columns. Use instead of ad-hoc UTC parsing.
func dateOnly(from string: String) -> Date? {
    _dateOnlyFormatter.date(from: String(string.prefix(10)))
}

/// Format a Date as "yyyy-MM-dd" in the device's local timezone — the same
/// contract used when encoding DATE columns.
func dateOnlyString(from date: Date) -> String {
    _dateOnlyFormatter.string(from: date)
}

extension String {
    /// Trimmed value, or nil if empty — for optional text columns.
    var nilIfBlank: String? {
        let t = trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}
