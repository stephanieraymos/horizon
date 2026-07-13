import SwiftUI

/// Circular person avatar: loads the member's photo (egress-safe cache) or falls
/// back to initials. Photos come from `fam_family_members.avatar_url`.
struct PersonAvatar: View {
    let name: String
    let avatarURL: String?
    var size: CGFloat = 28

    var body: some View {
        Group {
            if let s = avatarURL?.nilIfBlank, let url = URL(string: s) {
                CachedRemoteImage(url: url) { initials }
                    .scaledToFill()
            } else {
                initials
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }

    private var initials: some View {
        Circle().fill(Theme.Colors.brand.opacity(0.18))
            .overlay(
                Text(initialsText)
                    .font(.system(size: size * 0.4, weight: .semibold))
                    .foregroundStyle(Theme.Colors.brand)
            )
    }

    private var initialsText: String {
        let parts = name.split(separator: " ")
        let letters = parts.prefix(2).compactMap { $0.first }.map(String.init).joined()
        return letters.isEmpty ? "?" : letters.uppercased()
    }
}
