import SwiftUI
#if os(iOS)
import UIKit
typealias PlatformFont = UIFont
typealias PlatformColor = UIColor
#else
import AppKit
typealias PlatformFont = NSFont
typealias PlatformColor = NSColor
#endif

/// One styled run of text inside a block. Stored as JSON on the block so inline
/// bold/italic/color survives the jsonb round-trip and renders the same on both
/// platforms. The block's plain `text` stays as a mirror for search/preview.
struct RichRun: Codable, Hashable {
    var text: String
    var bold: Bool?
    var italic: Bool?
    var color: String?   // hex

    init(text: String, bold: Bool? = nil, italic: Bool? = nil, color: String? = nil) {
        self.text = text
        self.bold = bold
        self.italic = italic
        self.color = color
    }
}

extension Array where Element == RichRun {
    /// The plain concatenation, for the `text` mirror and previews.
    var plainText: String { map(\.text).joined() }

    /// Collapses adjacent runs that share styling, so the model stays compact.
    func coalesced() -> [RichRun] {
        var out: [RichRun] = []
        for run in self where !run.text.isEmpty {
            if var last = out.last,
               last.bold == run.bold, last.italic == run.italic, last.color == run.color {
                last.text += run.text
                out[out.count - 1] = last
            } else {
                out.append(run)
            }
        }
        return out
    }
}

/// Converts between our `[RichRun]` model and `NSAttributedString` for the
/// UITextView / NSTextView editor.
enum RichTextConverter {
    /// Builds an attributed string, applying each run's bold/italic/color over
    /// the given base font and color.
    static func attributed(_ runs: [RichRun], baseFont: PlatformFont,
                           baseColor: PlatformColor) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let source = runs.isEmpty ? [RichRun(text: "")] : runs
        for run in source {
            var font = baseFont
            if run.bold == true { font = font.withBold() }
            if run.italic == true { font = font.withItalic() }
            var attrs: [NSAttributedString.Key: Any] = [.font: font]
            if let hex = run.color, let c = Color(hex: hex) {
                attrs[.foregroundColor] = PlatformColor(c)
            } else {
                attrs[.foregroundColor] = baseColor
            }
            result.append(NSAttributedString(string: run.text, attributes: attrs))
        }
        return result
    }

    /// Reads styling back out of an attributed string into runs. `baseColor` is
    /// the editor's default text color; runs matching it record `color = nil` so
    /// default text stays adaptive (light/dark) instead of baking the resolved
    /// label color (e.g. white in dark mode) in as an explicit hex — which then
    /// reads as "no style" / invisible and makes styled words look like they
    /// reverted when a note is reopened.
    static func runs(from attr: NSAttributedString, baseColor: PlatformColor? = nil) -> [RichRun] {
        var out: [RichRun] = []
        let full = NSRange(location: 0, length: attr.length)
        let baseHex = baseColor.map(hexString(of:))
        attr.enumerateAttributes(in: full) { attrs, range, _ in
            let text = (attr.string as NSString).substring(with: range)
            guard !text.isEmpty else { return }
            var bold: Bool? = nil
            var italic: Bool? = nil
            if let font = attrs[.font] as? PlatformFont {
                let traits = font.fontDescriptor.symbolicTraits
                #if os(iOS)
                if traits.contains(.traitBold)   { bold = true }
                if traits.contains(.traitItalic) { italic = true }
                #else
                if traits.contains(.bold)   { bold = true }
                if traits.contains(.italic) { italic = true }
                #endif
            }
            var color: String? = nil
            if let pc = attrs[.foregroundColor] as? PlatformColor {
                let hex = hexString(of: pc)
                if hex != baseHex { color = hex }
            }
            out.append(RichRun(text: text, bold: bold, italic: italic, color: color))
        }
        return out.coalesced()
    }

    /// Hex for a platform color, resolved through SwiftUI so both platforms use
    /// the same representation.
    private static func hexString(of pc: PlatformColor) -> String {
        #if os(iOS)
        return Color(uiColor: pc).toHexString()
        #else
        return Color(nsColor: pc).toHexString()
        #endif
    }
}

extension PlatformFont {
    func withBold() -> PlatformFont {
        #if os(iOS)
        return addingTrait(.traitBold)
        #else
        return addingTrait(.bold)
        #endif
    }
    func withItalic() -> PlatformFont {
        #if os(iOS)
        return addingTrait(.traitItalic)
        #else
        return addingTrait(.italic)
        #endif
    }

    #if os(iOS)
    private func addingTrait(_ trait: UIFontDescriptor.SymbolicTraits) -> PlatformFont {
        let combined = fontDescriptor.symbolicTraits.union(trait)
        guard let desc = fontDescriptor.withSymbolicTraits(combined) else { return self }
        return PlatformFont(descriptor: desc, size: pointSize)
    }
    #else
    private func addingTrait(_ trait: NSFontDescriptor.SymbolicTraits) -> PlatformFont {
        let combined = fontDescriptor.symbolicTraits.union(trait)
        let desc = fontDescriptor.withSymbolicTraits(combined)
        return PlatformFont(descriptor: desc, size: pointSize) ?? self
    }
    #endif
}
