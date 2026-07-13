import SwiftUI

extension Color {
    init?(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var rgb: UInt64 = 0
        guard Scanner(string: cleaned).scanHexInt64(&rgb), cleaned.count == 6 else { return nil }
        self.init(
            red:   Double((rgb >> 16) & 0xFF) / 255,
            green: Double((rgb >> 8)  & 0xFF) / 255,
            blue:  Double( rgb        & 0xFF) / 255
        )
    }

    /// Equivalent of UIColor.systemGray6 on iOS, window background on macOS.
    static var systemFill6: Color {
        #if os(iOS)
        Color(uiColor: .systemGray6)
        #else
        Color(nsColor: .windowBackgroundColor)
        #endif
    }

    /// "#RRGGBB" for persisting a user-picked color.
    func toHexString() -> String {
        #if os(iOS)
        let c = UIColor(self)
        #else
        let c = NSColor(self).usingColorSpace(.sRGB) ?? NSColor(self)
        #endif
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        c.getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "#%02X%02X%02X",
                      Int((r * 255).rounded()), Int((g * 255).rounded()), Int((b * 255).rounded()))
    }
}

extension View {
    /// `.textInputAutocapitalization(.never)` on iOS; no-op on macOS.
    @ViewBuilder
    func noAutoCapitalize() -> some View {
        #if os(iOS)
        self.textInputAutocapitalization(.never)
        #else
        self
        #endif
    }
}
