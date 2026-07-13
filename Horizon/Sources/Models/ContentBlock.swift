import Foundation

/// One block in a Problem's rich document (Notion-style). Stored as a JSON
/// array in fam_issues.content. All payload fields are optional so block types
/// can evolve without breaking decoding of older rows.
struct ContentBlock: Identifiable, Codable, Hashable {
    var id: UUID
    var type: ContentBlockType
    var text: String?       // heading / text / todo / timeline body
    var checked: Bool?      // todo
    var label: String?      // keyFact label / contact name / timeline title
    var value: String?      // keyFact value
    var role: String?       // contact role / org
    var phone: String?      // contact
    var email: String?      // contact
    var date: String?       // timeline "YYYY-MM-DD"
    var filePath: String?   // image (storage path)
    var fileName: String?   // image
    var color: String?      // optional text color (hex) for text-bearing blocks
    var bgColor: String?    // optional background highlight (hex)
    var bold: Bool?         // whole-block bold
    var italic: Bool?       // whole-block italic
    var runs: [RichRun]?    // inline-styled text runs (rich text); `text` mirrors plain

    init(type: ContentBlockType) {
        self.id = UUID()
        self.type = type
        switch type {
        case .todo: checked = false
        default: break
        }
    }

    var textValue: String {
        get { text ?? "" }
        set { text = newValue }
    }

    /// A copy with a fresh id, for the "Duplicate" action.
    func duplicated() -> ContentBlock {
        var c = self; c.id = UUID(); return c
    }
}

enum ContentBlockType: String, Codable, CaseIterable, Identifiable {
    case heading, text, todo, bullet, numbered, code, keyFact = "keyfact", contact, timeline, image, link, divider

    var id: String { rawValue }

    var label: String {
        switch self {
        case .heading:  "Heading"
        case .text:     "Text"
        case .todo:     "To-do"
        case .bullet:   "Bulleted List"
        case .numbered: "Numbered List"
        case .code:     "Code"
        case .keyFact:  "Key Fact"
        case .contact:  "Contact"
        case .timeline: "Timeline Entry"
        case .image:    "Attachment"
        case .link:     "Link"
        case .divider:  "Divider"
        }
    }

    var icon: String {
        switch self {
        case .heading:  "textformat.size.larger"
        case .text:     "text.alignleft"
        case .todo:     "checklist"
        case .bullet:   "list.bullet"
        case .numbered: "list.number"
        case .code:     "chevron.left.forwardslash.chevron.right"
        case .keyFact:  "number.square"
        case .contact:  "person.crop.circle"
        case .timeline: "calendar.badge.clock"
        case .image:    "paperclip"
        case .link:     "link"
        case .divider:  "minus"
        }
    }

    /// Block types whose text can carry a custom color.
    var supportsTextColor: Bool {
        switch self {
        case .text, .heading, .todo, .bullet, .numbered, .code: true
        default: false
        }
    }

    /// Block types that accept a background highlight (everything but rules/images).
    var supportsBackground: Bool {
        switch self {
        case .divider, .image: false
        default: true
        }
    }

    /// Whole-block bold/italic only applies to plain text-bearing blocks.
    var supportsTextStyle: Bool { supportsTextColor }
}

/// A small palette of named text colors for rich blocks. Stored as hex on the
/// block so it survives JSON round-trips and renders the same on iOS and Mac.
enum BlockTextColor: String, CaseIterable, Identifiable {
    case red, orange, yellow, green, blue, purple, gray

    var id: String { rawValue }
    var name: String { rawValue.capitalized }
    var hex: String {
        switch self {
        case .red:    "#E25D5D"
        case .orange: "#E8915B"
        case .yellow: "#D9A92E"
        case .green:  "#4FA86B"
        case .blue:   "#4A90E2"
        case .purple: "#9B7BD4"
        case .gray:   "#8A8A8E"
        }
    }
}
