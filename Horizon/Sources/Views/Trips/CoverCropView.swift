import SwiftUI

/// Drag a photo to re-frame it — adjusts the focal point (0..1) it's shown at.
/// Shared by a plan's cover (saved to fam_trips) and a countdown's photo (saved
/// to fam_events); the host passes the photo, its current focus, the shape it's
/// shown at, and how to save.
///
/// The preview MUST be the banner's shape. It used to be a fixed 240 pt tall
/// while the banner is 170 pt, so a photo that overflowed the banner top-to-
/// bottom fit the preview exactly on that axis — every vertical drag did
/// nothing ("it won't let me drag to reposition", 2026-09-14) while the
/// horizontal axis, which the banner never shows, was the only one that moved.
struct CoverCropView: View {
    let cover: String?
    var title = "Adjust Cover"
    /// Width ÷ height of the banner being framed, measured where it's drawn.
    var bannerAspect: CGFloat = 393.0 / 170.0
    let onSave: (UnitPoint) async -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var focus: UnitPoint
    @State private var imageSize: CGSize?
    /// Where this drag began and the focus at that moment. Keyed by the touch's
    /// start location, so a gesture the system cancelled (no onEnded) can't
    /// leave a stale base that makes the next drag jump.
    @State private var dragAnchor: (start: CGPoint, focus: UnitPoint)?

    init(cover: String?, focus: UnitPoint, title: String = "Adjust Cover",
         bannerAspect: CGFloat? = nil, onSave: @escaping (UnitPoint) async -> Void) {
        self.cover = cover
        self.title = title
        self.onSave = onSave
        if let bannerAspect, bannerAspect.isFinite, bannerAspect > 0 { self.bannerAspect = bannerAspect }
        _focus = State(initialValue: focus)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Text(hint).font(.subheadline).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                GeometryReader { geo in
                    let frame = geo.size
                    let overflow = overflow(in: frame)
                    AdjustableCoverImage(cover: cover, focus: focus) {
                        Color.secondary.opacity(0.12)
                    }
                    .frame(width: frame.width, height: frame.height)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(.white.opacity(0.4), lineWidth: 1))
                    .contentShape(Rectangle())
                    // High priority + minimumDistance 0 so the image claims the
                    // touch before the sheet's drag-to-dismiss pan can steal it.
                    .highPriorityGesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                if dragAnchor == nil || dragAnchor?.start != value.startLocation {
                                    dragAnchor = (value.startLocation, focus)
                                }
                                let base = dragAnchor?.focus ?? focus
                                // Dragging the photo right reveals more of its left edge.
                                let dx = overflow.width  > 0 ? Double(value.translation.width  / overflow.width)  : 0
                                let dy = overflow.height > 0 ? Double(value.translation.height / overflow.height) : 0
                                focus = UnitPoint(x: min(max(base.x - dx, 0), 1),
                                                  y: min(max(base.y - dy, 0), 1))
                            }
                            .onEnded { _ in dragAnchor = nil }
                    )
                }
                .aspectRatio(bannerAspect, contentMode: .fit)
                .padding(.horizontal)

                Text("This only changes the framing — the photo isn't re-uploaded.")
                    .font(.caption).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center).padding(.horizontal)

                Spacer()
            }
            .padding(.top, 20)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let f = focus
                        Task { await onSave(f); dismiss() }
                    }
                }
            }
            // A vertical drag on the photo must reframe it, never pull the sheet
            // down (a UIKit pan that highPriorityGesture doesn't outrank) — and a
            // stray swipe shouldn't throw the adjustment away. Cancel/Save exist.
            .interactiveDismissDisabled()
            .task(id: cover) {
                guard let cover = cover?.nilIfBlank,
                      let img = await HorizonImageLoader.loadCover(cover) else { return }
                imageSize = img.size
            }
        }
    }

    /// How far the aspect-filled photo spills past the frame on each axis —
    /// recomputed every layout, so a rotation or a resized window can't leave
    /// it stale the way a one-time measurement did.
    private func overflow(in frame: CGSize) -> CGSize {
        guard let imageSize else { return .zero }
        let size = AdjustableCoverImage<Color>.layout(imageSize: imageSize, frame: frame, focus: focus).size
        return CGSize(width: max(0, size.width - frame.width), height: max(0, size.height - frame.height))
    }

    /// Says which way the photo can move — a banner-shaped photo only ever
    /// overflows on one axis, and a photo exactly the banner's shape can't move.
    private var hint: String {
        guard let imageSize, imageSize.height > 0 else { return "Drag to reposition" }
        let ratio = imageSize.width / imageSize.height
        if abs(ratio - bannerAspect) < 0.02 { return "This photo already fits the banner exactly" }
        return ratio > bannerAspect ? "Drag left or right to reposition" : "Drag up or down to reposition"
    }
}
