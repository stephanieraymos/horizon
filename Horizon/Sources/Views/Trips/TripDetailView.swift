import SwiftUI

struct TripDetailView: View {
    let trip: Trip
    @Environment(TripsStore.self) private var trips
    @Environment(\.dismiss) private var dismiss
    @State private var showEdit = false
    @State private var confirmDelete = false

    /// Always render the freshest copy from the store (after an edit).
    private var current: Trip { trips.trips.first { $0.id == trip.id } ?? trip }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                header
                overview
                if current.isSomeday { somedayCallout }
            }
            .padding()
        }
        .navigationTitle(current.name)
        #if !targetEnvironment(macCatalyst)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("Edit", systemImage: "pencil") { showEdit = true }
                    Button("Delete", systemImage: "trash", role: .destructive) { confirmDelete = true }
                } label: { Image(systemName: "ellipsis.circle") }
            }
        }
        .sheet(isPresented: $showEdit) { TripEditView(trip: current) }
        .confirmationDialog("Delete this trip?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete Trip", role: .destructive) {
                Task { await trips.delete(current); dismiss() }
            }
        }
    }

    private var header: some View {
        VStack(spacing: 8) {
            Text(current.countdownText)
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .foregroundStyle(current.isSomeday ? .purple : Theme.Colors.brand)
            Text(TripFormat.dateRange(current.departDate, current.returnDate))
                .font(.headline).foregroundStyle(.secondary)
            if let nights = current.nights {
                Text("\(nights) night\(nights == 1 ? "" : "s")")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
    }

    private var overview: some View {
        VStack(spacing: 0) {
            if let dest = destinationName {
                row("Destination", dest, "mappin.and.ellipse")
            }
            row("Status", current.status.label, current.status.systemImage)
            if let travelers = current.travelers, !travelers.isEmpty {
                row("Travelers", travelers.joined(separator: ", "), "person.2")
            }
            if let transport = current.transportation?.nilIfBlank {
                row("Transportation", transport, "car")
            }
            if let budget = TripFormat.money(current.budget) {
                row("Budget", budget, "dollarsign.circle")
            }
        }
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 12))
    }

    private var somedayCallout: some View {
        VStack(spacing: 10) {
            Label("This is a someday trip", systemImage: "sparkles")
                .font(.headline)
            Text("Add dates to move it into your upcoming trips.")
                .font(.callout).foregroundStyle(.secondary)
            Button("Add dates") { showEdit = true }
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color.purple.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
    }

    private var destinationName: String? {
        trips.destination(for: current)?.name ?? current.destination?.nilIfBlank
    }

    private func row(_ title: String, _ value: String, _ icon: String) -> some View {
        VStack(spacing: 0) {
            HStack {
                Label(title, systemImage: icon).foregroundStyle(.secondary)
                Spacer()
                Text(value).multilineTextAlignment(.trailing)
            }
            .padding(.horizontal).padding(.vertical, 12)
            Divider().padding(.leading)
        }
    }
}
