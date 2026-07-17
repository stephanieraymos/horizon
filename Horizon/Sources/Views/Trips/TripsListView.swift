import SwiftUI

// The old "Trips" tab has been merged into the unified `EventsBoardView`
// (Views/Events/EventsListView.swift), which shows trips and one-day events
// together with an All / Trips / Events filter. These row views live on so the
// board and the Someday tab can render trip rows.

/// A trip row that pushes `TripDetailView` via a destination-based link.
/// Used by the Someday tab. The Events board uses `TripRowLabel` directly with
/// value-based navigation so trip and event taps share one navigation path.
struct TripRow: View {
    let trip: Trip

    var body: some View {
        NavigationLink {
            TripDetailView(trip: trip)
        } label: {
            TripRowLabel(trip: trip)
        }
    }
}

/// The visual content of a trip row (cover, name, destination, date range,
/// countdown badge) with no navigation of its own.
struct TripRowLabel: View {
    let trip: Trip
    @Environment(TripsStore.self) private var trips

    var body: some View {
        HStack(spacing: 12) {
            if trip.coverPhotoURL?.nilIfBlank != nil {
                CoverImage(cover: trip.coverPhotoURL,
                           focus: UnitPoint(x: trip.coverFocusX, y: trip.coverFocusY)) { Color.secondary.opacity(0.12) }
                    .frame(width: 46, height: 46)
                    .clipShape(RoundedRectangle(cornerRadius: 9))
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(trip.name).font(.headline)
                if let subtitle = subtitle {
                    Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
                }
                Text(TripFormat.dateRange(trip.departDate, trip.returnDate))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            CountdownBadge(trip: trip)
        }
        .padding(.vertical, 2)
    }

    private var subtitle: String? {
        trips.destination(for: trip)?.name ?? trip.destination?.nilIfBlank
    }
}

struct CountdownBadge: View {
    let trip: Trip

    var body: some View {
        let text = trip.countdownText
        if !text.isEmpty {
            Text(text)
                .font(.caption).fontWeight(.semibold)
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(tint.opacity(0.15), in: Capsule())
                .foregroundStyle(tint)
        }
    }

    private var tint: Color {
        if trip.isSomeday { return .purple }
        if trip.countdownText == "Now" { return .green }
        if trip.isPast { return .secondary }
        return Theme.Colors.brand
    }
}
