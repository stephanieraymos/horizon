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

    /// Always the store's freshest copy, so a time or note saved here shows at once.
    private var current: FamilyEvent {
        isFromPeople ? event : (events.events.first { $0.id == event.id } ?? event)
    }

    private var canEdit: Bool { family.currentMember?.role == .admin && !isFromPeople }
    private var look: (symbol: String, tint: Color) { CountdownBuilder.appearance(for: current.eventType) }
    private var hasTime: Bool { TimeOfDay.components(current.eventTime) != nil }

    var body: some View {
        List {
            Section {
                VStack(spacing: 14) {
                    header
                    LiveCountdown(target: current.nextMoment, tint: look.tint, hasExactTime: hasTime)
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
                                .foregroundStyle(hasTime ? FamilyPalette.ink : Color.accentColor)
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
                Button("Plan something around it…", systemImage: "calendar.badge.plus") { planFrom = current }
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
        .sheet(item: $editingCountdown) { EventEditView(existing: $0) }
        .sheet(item: $openedTrip) { trip in
            NavigationStack { TripDetailView(trip: trip) }
        }
        .eventActions(event: $planFrom, allowLinkEdit: false, onOpenTrip: { openedTrip = $0 })
        .confirmationDialog("Delete “\(current.title)”?", isPresented: $confirmDelete,
                            titleVisibility: .visible) {
            Button("Delete countdown", role: .destructive) {
                let e = current
                Task { await events.delete(e); dismiss() }
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
        // Deleted from the editor sheet: nothing left to show.
        .onChange(of: events.events.contains { $0.id == event.id }) { _, stillThere in
            if !stillThere && !isFromPeople { dismiss() }
        }
    }

    /// With a photo: the photo, with Change (a PhotosPicker) and Remove (a
    /// Button) as two separate pills — never a Button layered over a picker,
    /// which on her phone sent taps to the picker (see CLAUDE.md, cover banner).
    @ViewBuilder
    private var photo: some View {
        if let cover = current.coverPhotoURL?.nilIfBlank {
            AdjustableCoverImage(cover: cover) { Color.secondary.opacity(0.12) }
                .frame(height: 160)
                .frame(maxWidth: .infinity)
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
