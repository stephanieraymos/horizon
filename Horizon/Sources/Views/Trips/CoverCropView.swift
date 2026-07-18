import SwiftUI

/// Drag the cover to re-frame it — adjusts the focal point (0..1) shown in the
/// banner, saved back to the trip.
struct CoverCropView: View {
    let trip: Trip
    @Environment(TripsStore.self) private var trips
    @Environment(\.dismiss) private var dismiss

    @State private var focus: UnitPoint
    @State private var imageSize: CGSize = .zero
    @GestureState private var dragStart: UnitPoint?

    private let bannerHeight: CGFloat = 240

    init(trip: Trip) {
        self.trip = trip
        _focus = State(initialValue: UnitPoint(x: trip.coverFocusX, y: trip.coverFocusY))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Text("Drag to reposition").font(.subheadline).foregroundStyle(.secondary)

                GeometryReader { geo in
                    AdjustableCoverImage(cover: trip.coverPhotoURL, focus: focus) {
                        Color.secondary.opacity(0.12)
                    }
                    .frame(height: bannerHeight)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(.white.opacity(0.4), lineWidth: 1))
                    .contentShape(Rectangle())
                    // High-priority so the drag wins over the sheet's swipe-to-dismiss,
                    // which otherwise eats vertical pans (the common case for wide banners).
                    .highPriorityGesture(
                        DragGesture()
                            .updating($dragStart) { _, state, _ in if state == nil { state = focus } }
                            .onChanged { value in
                                let range = panRange(frame: CGSize(width: geo.size.width, height: bannerHeight))
                                guard range.width > 0 || range.height > 0 else { return }
                                let base = dragStart ?? focus
                                let dx = range.width  > 0 ? Double(value.translation.width  / range.width)  : 0
                                let dy = range.height > 0 ? Double(value.translation.height / range.height) : 0
                                focus = UnitPoint(x: min(max(base.x - dx, 0), 1),
                                                  y: min(max(base.y - dy, 0), 1))
                            }
                    )
                }
                .frame(height: bannerHeight)
                .padding(.horizontal)

                Text("This only changes the framing — the photo isn't re-uploaded.")
                    .font(.caption).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center).padding(.horizontal)

                Spacer()
            }
            .padding(.top, 20)
            .navigationTitle("Adjust Cover")
            .navigationBarTitleDisplayMode(.inline)
            .interactiveDismissDisabled()
            .task(id: trip.coverPhotoURL) {
                guard let c = trip.coverPhotoURL?.nilIfBlank else { imageSize = .zero; return }
                imageSize = await HorizonImageLoader.loadCover(c)?.size ?? .zero
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task { await trips.saveCoverFocus(tripID: trip.id, x: focus.x, y: focus.y); dismiss() }
                    }
                }
            }
        }
    }

    /// How far the aspect-filled image overflows the frame in each axis — the
    /// pannable range. Computed live from the current frame so there's no async
    /// measurement to race with the gesture.
    private func panRange(frame: CGSize) -> CGSize {
        guard imageSize.width > 0, imageSize.height > 0, frame.width > 0 else { return .zero }
        let scaled = AdjustableCoverImage<Color>.layout(imageSize: imageSize, frame: frame, focus: focus).size
        return CGSize(width: max(0, scaled.width - frame.width),
                      height: max(0, scaled.height - frame.height))
    }
}
