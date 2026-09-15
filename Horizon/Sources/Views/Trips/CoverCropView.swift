import SwiftUI

/// Drag the cover to re-frame it — adjusts the focal point (0..1) shown in the
/// banner, saved back to the trip.
///
/// The preview MUST be the banner's shape. It used to be a fixed 240 pt tall
/// while the banner is 170 pt, so a photo that overflowed the banner top-to-
/// bottom fit the preview exactly on that axis — every vertical drag did
/// nothing ("it won't let me drag to reposition", 2026-09-14) while the
/// horizontal axis, which the banner never shows, was the only one that moved.
struct CoverCropView: View {
    let trip: Trip
    /// Width ÷ height of the banner being framed, measured where it's drawn.
    var bannerAspect: CGFloat = 393.0 / 170.0

    @Environment(TripsStore.self) private var trips
    @Environment(\.dismiss) private var dismiss

    @State private var focus: UnitPoint
    @State private var imageSize: CGSize?
    /// Focus when the finger went down. @State rather than @GestureState: a
    /// GestureState read inside onChanged can still be the previous value.
    @State private var dragStart: UnitPoint?

    init(trip: Trip, bannerAspect: CGFloat? = nil) {
        self.trip = trip
        if let bannerAspect, bannerAspect.isFinite, bannerAspect > 0 { self.bannerAspect = bannerAspect }
        _focus = State(initialValue: UnitPoint(x: trip.coverFocusX, y: trip.coverFocusY))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Text(hint).font(.subheadline).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                GeometryReader { geo in
                    let frame = geo.size
                    let overflow = overflow(in: frame)
                    AdjustableCoverImage(cover: trip.coverPhotoURL, focus: focus) {
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
                                let base = dragStart ?? focus
                                if dragStart == nil { dragStart = focus }
                                // Dragging the photo right reveals more of its left edge.
                                let dx = overflow.width  > 0 ? Double(value.translation.width  / overflow.width)  : 0
                                let dy = overflow.height > 0 ? Double(value.translation.height / overflow.height) : 0
                                focus = UnitPoint(x: min(max(base.x - dx, 0), 1),
                                                  y: min(max(base.y - dy, 0), 1))
                            }
                            .onEnded { _ in dragStart = nil }
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
            .navigationTitle("Adjust Cover")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task { await trips.saveCoverFocus(tripID: trip.id, x: focus.x, y: focus.y); dismiss() }
                    }
                }
            }
            .task(id: trip.coverPhotoURL) {
                guard let cover = trip.coverPhotoURL?.nilIfBlank,
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
