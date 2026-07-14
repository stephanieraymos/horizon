import SwiftUI
import PhotosUI

struct TripDetailView: View {
    let trip: Trip
    @Environment(TripsStore.self) private var trips
    @Environment(FamilyStore.self) private var family
    @Environment(TravelerProfilesStore.self) private var travelerProfiles
    @Environment(EventsStore.self) private var events
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
    @State private var calendarMessage: String?
    @State private var calendarIsError = false
    @State private var showPasteReservation = false
    @State private var showCoverCrop = false

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
                if !passportWarnings.isEmpty { passportCallout }
                overview
                if !mapEntries.isEmpty { TripMapView(entries: mapEntries) }
                TripPlacesSection(store: detail, familyID: current.familyID)
                TripWeatherSection(
                    trip: current,
                    destinationName: trips.destination(for: current)?.name ?? current.destination)
                if current.isSomeday { somedayCallout }
                reservationsSection
                itinerarySection
                notesSection
                TripTodosSection(store: detail, familyID: current.familyID)
                TripPackingSection(store: detail, trip: current)
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
                    if current.coverPhotoURL?.nilIfBlank != nil {
                        Button("Adjust cover crop", systemImage: "crop") { showCoverCrop = true }
                        Button("Remove cover photo", systemImage: "photo") {
                            Task { await trips.clearTripCover(tripID: current.id) }
                        }
                    }
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
                    if current.archived {
                        Button("Restore trip", systemImage: "arrow.uturn.backward") {
                            Task { await restore() }
                        }
                    } else {
                        Button("Mark as not going", systemImage: "xmark.bin") {
                            Task { await archive() }
                        }
                    }
                    Button("Delete trip", systemImage: "trash", role: .destructive) { confirmDelete = true }
                } label: { Image(systemName: "ellipsis.circle") }
            }
        }
        .task { await detail.load() }
        .task {
            if family.members.isEmpty { await family.load() }
            if travelerProfiles.profiles.isEmpty { await travelerProfiles.load() }
        }
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
        .sheet(isPresented: $showCoverCrop) { CoverCropView(trip: current) }
        .sheet(isPresented: $showPasteReservation) {
            PasteReservationSheet(familyID: current.familyID, tripID: current.id, onReview: { parsed in
                // Let the paste sheet finish dismissing before presenting the editor.
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 350_000_000)
                    editingReservation = parsed
                }
            }, onImportMany: { list in
                Task { for r in list { await detail.saveReservation(r) } }
            })
        }
        .confirmationDialog("Delete this trip?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete Trip", role: .destructive) {
                Task { await events.deleteForTrip(current.id); await trips.delete(current); dismiss() }
            }
        }
        .alert(calendarIsError ? "Couldn't add to Calendar" : "Added to Calendar",
               isPresented: Binding(get: { calendarMessage != nil },
                                    set: { if !$0 { calendarMessage = nil } })) {
            Button("OK", role: .cancel) { calendarMessage = nil }
        } message: { Text(calendarMessage ?? "") }
    }

    /// "Not going": archive the trip and drop its countdown.
    private func archive() async {
        await events.deleteForTrip(current.id)
        await trips.setArchived(current, true)
        dismiss()
    }

    private func restore() async {
        await trips.setArchived(current, false)
        // Rebuild the countdown for a dated trip.
        await events.syncCountdown(forTripID: current.id, familyID: current.familyID,
                                   name: current.name, departDate: current.departDate,
                                   createdBy: family.currentMember?.userID)
    }

    private func addToCalendar(_ res: Reservation) async {
        do {
            try await CalendarService.add(reservation: res, tripName: current.name)
            calendarIsError = false
            calendarMessage = "\(res.title.isEmpty ? res.type.label : res.title) was added to your calendar."
        } catch {
            calendarIsError = true
            calendarMessage = error.localizedDescription
        }
    }

    // MARK: Passport expiry warnings

    /// Travelers on this trip whose passport is expired or within 6 months of
    /// the departure date.
    private var passportWarnings: [(name: String, warning: PassportWarning)] {
        guard current.departDate != nil || !current.isSomeday else { return [] }
        let names = current.travelers ?? []
        return names.compactMap { name in
            guard let member = family.members.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }),
                  let profile = travelerProfiles.profile(for: member.id),
                  let warning = profile.passportValidityWarning(forDeparture: current.departDate)
            else { return nil }
            return (name, warning)
        }
    }

    private var passportCallout: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Passport check", systemImage: "exclamationmark.triangle.fill")
                .font(.subheadline.bold())
                .foregroundStyle(.orange)
            ForEach(passportWarnings, id: \.name) { w in
                Text(w.warning == .expired
                     ? "\(w.name)'s passport is expired."
                     : "\(w.name)'s passport expires within 6 months of departure — some countries require 6 months' validity.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: Header + overview

    private var coverBanner: some View {
        PhotosPicker(selection: $coverItem, matching: .images) {
            Group {
                if current.coverPhotoURL?.nilIfBlank != nil {
                    AdjustableCoverImage(cover: current.coverPhotoURL,
                                         focus: UnitPoint(x: current.coverFocusX, y: current.coverFocusY)) {
                        Color.secondary.opacity(0.12)
                    }
                } else {
                    ZStack {
                        LinearGradient(colors: [Theme.Colors.brand.opacity(0.35), Theme.Colors.brand.opacity(0.15)],
                                       startPoint: .top, endPoint: .bottom)
                        Label("Add cover photo", systemImage: "photo.badge.plus").foregroundStyle(.white)
                    }
                }
            }
            .frame(height: 170)
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(alignment: .bottomTrailing) {
                if current.coverPhotoURL?.nilIfBlank != nil {
                    Label("Change", systemImage: "camera.fill")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(.ultraThinMaterial, in: Capsule())
                        .padding(10)
                }
            }
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
                    Button("Paste confirmation…", systemImage: "doc.on.clipboard") {
                        showPasteReservation = true
                    }
                    Divider()
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
                                if res.startAt != nil {
                                    Button("Add to Calendar", systemImage: "calendar.badge.plus") {
                                        Task { await addToCalendar(res) }
                                    }
                                }
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
        for tp in detail.tripPlaces {
            if let place = trips.places.first(where: { $0.id == tp.placeID }),
               let addr = place.address?.nilIfBlank {
                out.append((place.name, addr, place.categoryIcon))
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
