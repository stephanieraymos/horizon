import Foundation
import Supabase

/// Calls the `parse-capture` edge function to turn a dictated/typed note into
/// structured trip items. The function returns raw items; the app resolves
/// people, dates, and stores (see QuickCaptureView).
enum CaptureParser {
    struct Context: Encodable {
        var travelers: [String]
        var currentMemberName: String?
        var stores: [String]
        var packingCategories: [String]
        var departDate: String?
        var returnDate: String?
        var tripName: String?
    }

    private struct Payload: Encodable {
        var text: String
        var context: Context
    }

    /// ISO yyyy-MM-dd for passing trip dates to the parser.
    static func isoDay(_ date: Date?) -> String? {
        guard let date else { return nil }
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

    static func parse(text: String, context: Context) async throws -> ParsedCapture {
        let data = try JSONEncoder().encode(Payload(text: text, context: context))
        let options = FunctionInvokeOptions(
            headers: ["Content-Type": "application/json"],
            body: data
        )
        return try await supabase.functions.invoke("parse-capture", options: options)
    }
}
