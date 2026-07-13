import SwiftUI

enum Theme {
    enum Colors {
        /// Horizon brand — a dusk teal-blue. Matches Assets/AccentColor.
        static let brand = Color(red: 0.200, green: 0.549, blue: 0.722)
        static let brandAmber = Color(hex: "#F59E0B") ?? .orange

        /// Card / row surface above the grouped background.
        static var card: Color {
            #if os(iOS)
            Color(uiColor: .secondarySystemGroupedBackground)
            #else
            Color(nsColor: .controlBackgroundColor)
            #endif
        }
        /// Page background behind cards.
        static var background: Color {
            #if os(iOS)
            Color(uiColor: .systemGroupedBackground)
            #else
            Color(nsColor: .windowBackgroundColor)
            #endif
        }
        /// Hairline border for cards.
        static let hairline = Color.primary.opacity(0.06)
    }

    enum Spacing {
        static let xs: CGFloat = 4
        static let s:  CGFloat = 8
        static let m:  CGFloat = 16
        static let l:  CGFloat = 24
    }
}
