import SwiftUI
import PhotosUI

struct TripDetailView: View {
    let trip: Trip
    @Environment(TripsStore.self) private var trips
    @Environment(FamilyStore.self) private var family
    @Environment(\.dismiss) private var dismiss

    @State private var detail: TripDetailStore
    @State private var showEdit = false
    @State private var confirmDelete = false
    @State private var editingReservation: Reservation?
    @State private var editingDay: ItineraryDay?
    @State private var coverItem: PhotosPickerItem?
    @State private var showMemories = false
    @State private var showMoodBoard = false
    @State private var coverError: String?

    init(trip: Trip) {
        self.trip = trip
        _detail = State(initialValue: TripDetailStore(tripID: trip.id))
    }

    /// Always render the freshest copy from the store (after an edit).
    private var current: Trip { trips.trips.first { $0.id == trip.id } ?? trip }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                coverBanner
                header
                travelersStrip
                overview
                if !mapEntries.isEmpty { TripMapView(entries: mapEntries) }
                if current.isSomeday { somedayCallout }
                reservationsSection
                itinerarySection
                notesSection
                TripTodosSection(store: detail, familyID: current.familyID)
                TripPackingSection(store: detail, travelerNames: current.travelers ?? [])
                TripPurchasesSection(store: detail, familyID: current.familyID)
                TripExpensesSection(store: detail, trip: current)
                TripDocumentsSection(store: detail, familyID: current.familyID)
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
                    Button("Edit trip", systemImage: "pencil") { showEdit = true }
                    Button("Duplicate trip", systemImage: "plus.square.on.square") {
                        Task { await duplicate() }
                    }
                    Button("Mood Board", systemImage: "square.grid.2x2") { showMoodBoard = true }
                    Button("Memories", systemImage: "photo.on.rectangle.angled") { showMemories = true }
                    if current.isUpcoming, current.departDate != nil, TripLiveActivityManager.isSupported {
                        if TripLiveActivityManager.isRunning(tripName: current.name) {
                            Button("Stop Live Activity", systemImage: "stop.circle") {
                                TripLiveActivityManager.stop(tripName: current.name)
                            }
                        } else {
                            Button("Track countdown", systemImage: "timer") {
                                TripLiveActivityManager.start(trip: current)
                            }
                        }
                    }
                    Button("Delete trip", systemImage: "trash", role: .destructive) { confirmDelete = true }
                } label: { Image(systemName: "ellipsis.circle") }
            }
        }
        .task { await detail.load() }
        .sheet(isPresented: $showEdit) { TripEditView(trip: current) }
        .sheet(item: $editingReservation) { res in
            ReservationEditView(reservation: res).environment(detail)
        }
        .sheet(item: $editingDay) { day in
            ItineraryDayEditView(day: day).environment(detail)
        }
        .sheet(isPresented: $showMemories) {
            MemoriesView(store: detail, tripName: current.name)
        }
        .sheet(isPresented: $showMoodBoard) {
            TripMoodBoardView(tripID: current.id, familyID: current.familyID, tripName: current.name)
        }
        .confirmationDialog("Delete this trip?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete Trip", role: .destructive) {
                Task { await trips.delete(current); dismiss() }
            }
        }
    }

    // MARK: Header + overview

    private var coverBanner: some View {
        PhotosPicker(selection: $coverItem, matching: .images) {
            CoverImage(cover: current.coverPhotoURL) {
                ZStack {
                    LinearGradient(colors: [Theme.Colors.brand.opacity(0.35), Theme.Colors.brand.opacity(0.15)],
                                   startPoint: .top, endPoint: .bottom)
                    Label("Add cover photo", systemImage: "photo.badge.plus").foregroundStyle(.white)
                }
            }
            .frame(height: 170)
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .onChange(of: coverItem) { _, item in
            guard let item else { return }
            Task {
                guard let data = try? await item.loadTransferable(type: Data.self) else {
                    coverError = "Couldn't read that photo. Try a different one."
                    coverItem = nil; return
                }
                let ok = await trips.setTripCover(tripID: current.id, familyID: current.familyID, imageData: data)
                if !ok { coverError = trips.errorMessage ?? "Upload failed. Check your connection." }
                coverItem = nil
            }
        }
        .alert("Couldn't add cover", isPresented: Binding(
            get: { coverError != nil }, set: { if !$0 { coverError = nil } })) {
            Button("OK", role: .cancel) { coverError = nil }
        } message: { Text(coverError ?? "") }
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

    @ViewBuilder
    private var travelersStrip: some View {
        if let travelers = current.travelers, !travelers.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(travelers, id: \.self) { name in
                        VStack(spacing: 4) {
                            PersonAvatar(name: name, avatarURL: family.members.first { $0.name == name }?.avatarURL, size: 44)
                            Text(name.split(separator: " ").first.map(String.init) ?? name)
                                .font(.caption).lineLimit(1)
                        }
                    }
                }
                .padding(.horizontal, 4)
            }
        }
    }

    private var overview: some View {
        VStack(spacing: 0) {
            if let dest = destinationName { row("Destination", dest, "mappin.and.ellipse") }
            row("Status", current.status.label, current.status.systemImage)
            if let transport = current.transportation?.nilIfBlank { row("Transportation", transport, "car") }
            if let budget = TripFormat.money(current.budget) { row("Budget", budget, "dollarsign.circle") }
        }
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: Reservations

    private var reservationsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Reservations") {
                Menu {
                    ForEach(ReservationType.allCases, id: \.self) { type in
                        Button(type.label, systemImage: type.systemImage) {
                            editingReservation = Reservation(familyID: current.familyID,
                                                             tripID: current.id, type: type)
                        }
                    }
                } label: { Image(systemName: "plus.circle.fill").font(.title3) }
            }

            if detail.reservations.isEmpty {
                emptyHint("No flights, lodging, or bookings yet.")
            } else {
                ForEach(detail.reservationsByType, id: \.type) { group in
                    ForEach(group.items) { res in
                        ReservationCard(reservation: res)
                            .onTapGesture { editingReservation = res }
                            .contextMenu {
                                Button("Edit") { editingReservation = res }
                                Button("Delete", role: .destructive) {
                                    Task { await detail.deleteReservation(res) }
                                }
                            }
                    }
                }
            }
        }
    }

    // MARK: Itinerary

    private var itinerarySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Itinerary") {
                Button {
                    editingDay = ItineraryDay(tripID: current.id, dayDate: current.departDate ?? Date())
                } label: { Image(systemName: "plus.circle.fill").font(.title3) }
            }

            if detail.itinerary.isEmpty {
                emptyHint("Plan a day-by-day schedule.")
            } else {
                ForEach(detail.itinerary) { day in
                    ItineraryDayCard(day: day)
                        .onTapGesture { editingDay = day }
                        .contextMenu {
                            Button("Edit") { editingDay = day }
                            Button("Delete", role: .destructive) {
                                Task { await detail.deleteDay(day) }
                            }
                        }
                }
            }
        }
    }

    private var notesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Notes").font(.title3.bold())
            NavigationLink { TripNotesEditorView(trip: current) } label: {
                HStack {
                    Image(systemName: "note.text").foregroundStyle(Theme.Colors.brand)
                    Text(notesPreview ?? "Add trip notes")
                        .foregroundStyle(notesPreview == nil ? .secondary : .primary)
                        .lineLimit(2)
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                }
                .padding()
                .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
        }
    }

    private var notesPreview: String? {
        current.notesContent?.first { ($0.text?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false) }?.text
    }

    private var somedayCallout: some View {
        VStack(spacing: 10) {
            Label("This is a someday trip", systemImage: "sparkles").font(.headline)
            Text("Add dates to move it into your upcoming trips.")
                .font(.callout).foregroundStyle(.secondary)
            Button("Add dates") { showEdit = true }.buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity).padding()
        .background(Color.purple.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: Helpers

    private func duplicate() async {
        let copy = Trip(familyID: current.familyID, name: current.name + " (copy)",
                        destination: current.destination, destinationID: current.destinationID,
                        travelers: current.travelers, transportation: current.transportation,
                        status: .planning, budget: current.budget, placeID: current.placeID)
        await trips.save(copy)
        await detail.copyReusableItems(to: copy.id)
        dismiss()
    }

    private var destinationName: String? {
        trips.destination(for: current)?.name ?? current.destination?.nilIfBlank
    }

    /// Everything with a location, for one combined trip map: reservations +
    /// every itinerary stop (falling back to the destination if nothing else).
    private var mapEntries: [(name: String, address: String, systemImage: String)] {
        var out: [(String, String, String)] = []
        for r in detail.reservations {
            if let addr = r.address?.nilIfBlank {
                out.append((r.title, addr, r.type.systemImage))
            }
        }
        for day in detail.itinerary {
            for act in day.activities {
                if let loc = act.locationName?.nilIfBlank {
                    out.append((act.title.nilIfBlank ?? loc, loc, "mappin"))
                }
            }
        }
        if out.isEmpty, let dest = destinationName {
            out.append((dest, dest, "mappin.and.ellipse"))
        }
        return out.map { (name: $0.0, address: $0.1, systemImage: $0.2) }
    }

    private func sectionHeader<Trailing: View>(_ title: String, @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack {
            Text(title).font(.title3.bold())
            Spacer()
            trailing().tint(Theme.Colors.brand)
        }
    }

    private func emptyHint(_ text: String) -> some View {
        Text(text).font(.callout).foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding().background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 12))
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

// MARK: - Cards

private struct ReservationCard: View {
    let reservation: Reservation

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: reservation.type.systemImage)
                .font(.title3).foregroundStyle(Theme.Colors.brand)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(reservation.title).font(.headline)
                if let when = whenText { Text(when).font(.caption).foregroundStyle(.secondary) }
                if let conf = reservation.confirmationNumber?.nilIfBlank {
                    Text("Conf: \(conf)").font(.caption2).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if let cost = TripFormat.money(reservation.costDollars) {
                Text(cost).font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .padding().background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 12))
    }

    private var whenText: String? {
        guard let start = reservation.startAt else { return nil }
        let s = start.formatted(.dateTime.month(.abbreviated).day().hour().minute())
        if let end = reservation.endAt {
            return "\(s) → \(end.formatted(.dateTime.hour().minute()))"
        }
        return s
    }
}

private struct ItineraryDayCard: View {
    let day: ItineraryDay

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(day.dayDate.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()))
                .font(.headline)
            if day.activities.isEmpty {
                Text("No activities").font(.caption).foregroundStyle(.secondary)
            } else {
                ForEach(day.activities) { act in
                    HStack(alignment: .top, spacing: 8) {
                        if let time = act.time?.nilIfBlank {
                            Text(time).font(.caption.monospaced()).foregroundStyle(Theme.Colors.brand)
                                .frame(width: 62, alignment: .leading)
                        } else {
                            Text("•").frame(width: 62, alignment: .leading).foregroundStyle(.secondary)
                        }
                        VStack(alignment: .leading, spacing: 1) {
                            Text(act.title).font(.subheadline)
                            if let loc = act.locationName?.nilIfBlank {
                                Text(loc).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding().background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 12))
    }
}
