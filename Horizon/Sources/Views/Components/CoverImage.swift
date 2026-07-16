import SwiftUI

/// Renders a cover photo. Accepts either an http(s) URL or a private
/// Storage path — both go through the egress-safe cached loaders. Fills its
/// frame aspect-fill, anchored to `focus` (the trip's saved focal point) so a
/// thumbnail shows the same part of the photo the detail banner does.
struct CoverImage<Placeholder: View>: View {
    let cover: String?
    var focus: UnitPoint = .center
    @ViewBuilder var placeholder: () -> Placeholder

    var body: some View {
        AdjustableCoverImage(cover: cover, focus: focus, placeholder: placeholder)
    }
}
