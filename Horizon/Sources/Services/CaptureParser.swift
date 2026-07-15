import Foundation
import Supabase

/// An error the edge function reported (its JSON `{error: ...}` body), surfaced
/// so the UI can show the real cause (e.g. a missing API key) instead of a
/// generic network message.
struct CaptureServerError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

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

    /// yyyy-MM-dd (device-local, matching how the app encodes DATE columns) for
    /// passing trip dates to the parser.
    static func isoDay(_ date: Date?) -> String? {
        guard let date else { return nil }
        return dateOnlyString(from: date)
    }

    static func parse(text: String, context: Context) async throws -> ParsedCapture {
        let data = try JSONEncoder().encode(Payload(text: text, context: context))
        let options = FunctionInvokeOptions(
            headers: ["Content-Type": "application/json"],
            body: data
        )
        do {
            return try await supabase.functions.invoke("parse-capture", options: options)
        } catch let FunctionsError.httpError(_, data) {
            // Surface the function's own error message (e.g. missing API key)
            // rather than the opaque httpError.
            struct Body: Decodable { let error: String }
            if let body = try? JSONDecoder().decode(Body.self, from: data) {
                throw CaptureServerError(message: body.error)
            }
            throw CaptureServerError(message: "The parser returned an error.")
        }
    }
}
