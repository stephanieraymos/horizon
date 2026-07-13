import SwiftUI

/// Renders a cover photo. Accepts either an http(s) URL or a private
/// Storage path — both go through the egress-safe cached loaders.
struct CoverImage<Placeholder: View>: View {
    let cover: String?
    @ViewBuilder var placeholder: () -> Placeholder

    var body: some View {
        if let c = cover?.nilIfBlank {
            if c.hasPrefix("http"), let url = URL(string: c) {
                CachedRemoteImage(url: url) { placeholder() }.scaledToFill()
            } else {
                CachedStorageImage(path: c) { placeholder() }.scaledToFill()
            }
        } else {
            placeholder()
        }
    }
}
