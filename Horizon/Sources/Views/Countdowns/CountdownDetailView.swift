import SwiftUI
import PhotosUI
import AppShellKit

/// One countdown, opened from its row: a live clock to the second, the exact
/// time (editable), a note, and what it is. Plans don't come here — a plan's
/// row opens the plan, whose header carries the same live clock.
///
/// A People birthday has no `fam_events` row, so it has nothing to put a time
/// or a note on; it shows the clock and offers to plan around it (which can
/// turn it into a real countdown of its own).
/// What a tapped countdown opens. Held in the HOST screen's state (not a
/// NavigationLink inside a row), so the pushed detail can't pop when its row
/// moves or disappears — and so where it came from is decided at the tap, not
/// re-derived from the store (which once turned a just-deleted countdown into
/// a "People birthday" ghost screen on Home).
enum CountdownRoute: Hashable {
    case countdown(FamilyEvent)
    case birthday(FamilyEvent)

    var event: FamilyEvent {
        switch self { case .countdown(let e), .birthday(let e): return e }
    }
    var isFromPeople: Bool {
        if case .birthday = self { return true }
        return false
    }
}

struct CountdownDetailView: View {
    let event: FamilyEvent
    /// True for a birthday synthesized from People (no row of its own).
    var isFromPeople = false

    @Environment(EventsStore.self) private var events
    @Environment(FamilyStore.self) private var family
    @Environment(\.dismiss) private var dismiss

    @State private var editingTime = false
    @State private var editingNote = false
    @State private var editingCountdown: FamilyEvent?
    @State private var planFrom: FamilyEvent?
    @State private var openedTrip: Trip?
    @State private var confirmDelete = false
    @State private var photoItem: PhotosPickerItem?
    @State private var photoError: String?
    @State private var saveError: String?
    @State private var showReframe = false
    /// Measured shape of the photo preview — which is the card's shape (same
    /// width, same height), so Reframe previews exactly what the card shows.
    @State private var photoAspect: CGFloat?
    /// The small countdown card's height — the SAME @ScaledMetric as
    /// CountdownCard.smallHeight, so preview and card grow together with text size.
    @ScaledMetric(relativeTo: .headline) private var cardHeight: CGFloat = 148

    /// Always the store's freshest copy, so a time or note saved here shows at once.
    private var current: FamilyEvent {
        isFromPeople ? event : (events.events.first { $0.id == event.id } ?? event)
    }

    /// fam_events / fam_trips writes are admin-only (RLS).
    private var isAdmin: Bool { family.currentMember?.role == .admin }
    private var canEdit: Bool { isAdmin && !isFromPeople }
    private var look: (symbol: String, tint: Color) { CountdownBuilder.appearance(for: current.eventType) }
    private var hasTime: Bool { TimeOfDay.components(current.eventTime) != nil }

    var body: some View {
        List {
            Section {
                VStack(spacing: 14) {
                    header
                    LiveCountdown(target: current.nextMoment, tint: look.tint, hasExactTime: hasTime,
                                  canSetTime: canEdit)
                }
                .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                .listRowBackground(Color.clear)
            }

            if canEdit || current.coverPhotoURL?.nilIfBlank != nil {
                Section {
                    photo
                        .listRowInsets(EdgeInsets())
                } header: {
                    Text("Photo")
                } footer: {
                    if canEdit && current.coverPhotoURL?.nilIfBlank == nil {
                        Text("Shown behind the countdown on its card.")
                    }
                }
            }

            Section("When") {
                LabeledContent("Date", value: current.nextMoment.formatted(date: .complete, time: .omitted))
                if canEdit {
                    Button { editingTime = true } label: {
                        LabeledContent("Time") {
                            Text(TimeOfDay.label(current.eventTime) ?? "All day — add a time")
                                .foregroundStyle(hasTime ? FamilyPalette.ink : Theme.Colors.brand)
                        }
                        // A plain-style Button only hits where its label draws —
                        // without this the gap between "Time" and the value is dead.
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                } else if let t = TimeOfDay.label(current.eventTime) {
                    LabeledContent("Time", value: t)
                }
                if current.isAnnual {
                    LabeledContent("Repeats", value: "Every year")
                }
                if let detail = CountdownBuilder.detail(for: current) {
                    LabeledContent("What", value: detail)
                }
            }

            if !isFromPeople {
                Section("Note") {
                    if let note = current.description?.nilIfBlank {
                        Text(note)
                            .foregroundStyle(FamilyPalette.ink)
                            .textSelection(.enabled)
                        if canEdit {
                            Button("Edit note", systemImage: "pencil") { editingNote = true }
                        }
                    } else if canEdit {
                        Button("Add a note", systemImage: "note.text.badge.plus") { editingNote = true }
                    } else {
                        Text("No note").foregroundStyle(FamilyPalette.inkSecondary)
                    }
                }
            }

            if let members = current.members, !members.isEmpty {
                Section("Who") {
                    Text(members.joined(separator: ", ")).foregroundStyle(FamilyPalette.ink)
                }
            }

            Section {
                if isAdmin {
                    Button("Plan something around it…", systemImage: "calendar.badge.plus") { planFrom = current }
                }
                if canEdit {
                    Button("Delete countdown", systemImage: "trash", role: .destructive) { confirmDelete = true }
                }
            } footer: {
                if isFromPeople {
                    Text("This birthday comes from People. Customize it as a countdown to give it a time or a note.")
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        // The Countdowns list's readable width, so on iPad/Mac the photo here is
        // the card's width too (and Reframe previews the card's shape).
        .frame(maxWidth: 760)
        .frame(maxWidth: .infinity)
        .background(FamilyPalette.groundGrouped)
        .navigationTitle(current.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if canEdit {
                ToolbarItem(placement: .primaryAction) {
                    Button("Edit") { editingCountdown = current }
                }
            }
        }
        .sheet(isPresented: $editingTime) {
            TimeOfDaySheet(title: "Time", current: current.eventTime) { t in
                let id = current.id
                Task {
                    if !(await events.saveTime(eventID: id, time: t)) {
                        saveError = events.error ?? "Couldn't save the time. Check your connection."
                    }
                }
            }
        }
        .sheet(isPresented: $showReframe) {
            let id = current.id
            CoverCropView(cover: current.coverPhotoURL,
                          focus: UnitPoint(x: current.coverFocusX, y: current.coverFocusY),
                          title: "Adjust Photo", bannerAspect: photoAspect) { f in
                await events.saveCoverFocus(eventID: id, x: f.x, y: f.y)
            }
        }
        .sheet(isPresented: $editingNote) {
            CountdownNoteSheet(title: "Note", current: current.description) { n in
                let id = current.id
                Task {
                    if !(await events.saveNote(eventID: id, note: n)) {
                        saveError = events.error ?? "Couldn't save the note. Check your connection."
                    }
                }
            }
        }
        // Deleted from the editor: pop once the sheet has finished closing — a pop
        // issued while it's still animating away can be dropped.
        .sheet(item: $editingCountdown, onDismiss: {
            if !isFromPeople && !events.events.contains(where: { $0.id == event.id }) { dismiss() }
        }) { EventEditView(existing: $0) }
        .sheet(item: $openedTrip) { trip in
            NavigationStack { TripDetailView(trip: trip) }
        }
        .eventActions(event: $planFrom, allowLinkEdit: false, onOpenTrip: { openedTrip = $0 })
        .confirmationDialog("Delete “\(current.title)”?", isPresented: $confirmDelete,
                            titleVisibility: .visible) {
            Button("Delete countdown", role: .destructive) {
                let e = current
                Task {
                    await events.delete(e)
                    // Only leave if it actually went (a failed delete keeps the row).
                    if !events.events.contains(where: { $0.id == e.id }) { dismiss() }
                }
            }
        }
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            guard let familyID = family.familyID else {
                photoItem = nil
                photoError = "Your family hasn't loaded yet — try again in a moment."
                return
            }
            Task {
                guard let jpeg = await item.loadUploadJPEG() else {
                    photoError = "Couldn't read that photo. If it's stored in iCloud, open it in Photos once, then try again."
                    photoItem = nil; return
                }
                let ok = await events.setCover(eventID: current.id, familyID: familyID, imageData: jpeg)
                if !ok { photoError = events.error ?? "Upload failed. Check your connection." }
                photoItem = nil
            }
        }
        .alert("Couldn't add photo", isPresented: Binding(
            get: { photoError != nil }, set: { if !$0 { photoError = nil } })) {
            Button("OK", role: .cancel) { photoError = nil }
        } message: { Text(photoError ?? "") }
        .alert("Couldn't save", isPresented: Binding(
            get: { saveError != nil }, set: { if !$0 { saveError = nil } })) {
            Button("OK", role: .cancel) { saveError = nil }
        } message: { Text(saveError ?? "") }
    }

    /// With a photo: the photo, with Change (a PhotosPicker) and Remove (a
    /// Button) as two separate pills — never a Button layered over a picker,
    /// which on her phone sent taps to the picker (see CLAUDE.md, cover banner).
    @ViewBuilder
    private var photo: some View {
        if let cover = current.coverPhotoURL?.nilIfBlank {
            AdjustableCoverImage(cover: cover,
                                 focus: UnitPoint(x: current.coverFocusX, y: current.coverFocusY)) {
                Color.secondary.opacity(0.12)
            }
                // The countdown card's height, so this preview IS the card's framing.
                .frame(height: cardHeight)
                .frame(maxWidth: .infinity)
                .onGeometryChange(for: CGFloat.self) { $0.size.width / max($0.size.height, 1) } action: {
                    photoAspect = $0
                }
                .clipped()
                .overlay(alignment: .bottom) {
                    if canEdit {
                        HStack {
                            Button {
                                Task { await events.saveCover(eventID: current.id, path: nil) }
                            } label: {
                                Label("Remove", systemImage: "trash")
                                    .font(.caption2.weight(.semibold))
                                    .padding(.horizontal, 10).padding(.vertical, 6)
                                    .glassSurface(in: Capsule(), fallback: .ultraThinMaterial)
                                    .contentShape(Capsule())
                            }
                            .buttonStyle(.plain)
                            Spacer()
                            // Separate pills, nothing layered under any of them — a
                            // Button over a PhotosPicker sent taps to the picker.
                            Button { showReframe = true } label: {
                                Label("Reframe", systemImage: "crop")
                                    .font(.caption2.weight(.semibold))
                                    .padding(.horizontal, 10).padding(.vertical, 6)
                                    .glassSurface(in: Capsule(), fallback: .ultraThinMaterial)
                                    .contentShape(Capsule())
                            }
                            .buttonStyle(.plain)
                            PhotosPicker(selection: $photoItem, matching: .images) {
                                Label("Change", systemImage: "camera.fill")
                                    .font(.caption2.weight(.semibold))
                                    .padding(.horizontal, 10).padding(.vertical, 6)
                                    .glassSurface(in: Capsule(), fallback: .ultraThinMaterial)
                                    .contentShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(10)
                    }
                }
        } else {
            // Read state OUTSIDE the label closure: PhotosPicker's label is a
            // Sendable closure under Swift 6 and can't touch main-actor state.
            let title = photoItem == nil ? "Add a photo" : "Uploading…"
            PhotosPicker(selection: $photoItem, matching: .images) {
                Label(title, systemImage: "photo.badge.plus")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20).padding(.vertical, 12)
                    .contentShape(Rectangle())
            }
        }
    }

    private var header: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle().fill(look.tint.opacity(0.15))
                if let emoji = current.emoji?.nilIfBlank {
                    Text(emoji).font(.system(size: 34))
                } else {
                    Image(systemName: look.symbol)
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(look.tint)
                }
            }
            .frame(width: 68, height: 68)
            .accessibilityHidden(true)
            Text(current.title)
                .font(.title2.weight(.bold))
                .foregroundStyle(FamilyPalette.ink)
                .multilineTextAlignment(.center)
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(FamilyPalette.inkSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    private var subtitle: String {
        let m = current.nextMoment
        let date = m.formatted(.dateTime.weekday(.wide).month(.wide).day().year())
        guard let t = TimeOfDay.label(current.eventTime) else { return date }
        return "\(date) at \(t)"
    }
}
