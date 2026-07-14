import SwiftUI

/// Drag the cover to re-frame it — adjusts the focal point (0..1) shown in the
/// banner, saved back to the trip.
struct CoverCropView: View {
    let trip: Trip
    @Environment(TripsStore.self) private var trips
    @Environment(\.dismiss) private var dismiss

    @State private var focus: UnitPoint
    @State private var overflow: CGSize = .zero
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
                    .background(GeometryReader { _ in Color.clear
                        .task(id: trip.coverPhotoURL) { await measureOverflow(frame: CGSize(width: geo.size.width, height: bannerHeight)) }
                    })
                    .gesture(
                        DragGesture()
                            .updating($dragStart) { _, state, _ in if state == nil { state = focus } }
                            .onChanged { value in
                                let base = dragStart ?? focus
                                let dx = overflow.width  > 0 ? Double(value.translation.width  / overflow.width)  : 0
                                let dy = overflow.height > 0 ? Double(value.translation.height / overflow.height) : 0
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

    private func measureOverflow(frame: CGSize) async {
        guard let cover = trip.coverPhotoURL?.nilIfBlank,
              let img = await HorizonImageLoader.loadCover(cover) else { return }
        overflow = AdjustableCoverImage<Color>.layout(imageSize: img.size, frame: frame, focus: focus).size
        overflow = CGSize(width: max(0, overflow.width - frame.width),
                          height: max(0, overflow.height - frame.height))
    }
}
