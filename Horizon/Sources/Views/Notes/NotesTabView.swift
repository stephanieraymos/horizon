import SwiftUI
import DuoKit

/// Notes is presented as a sheet from Home (not a tab), but on regular width the
/// sheet itself is spacious enough to earn a real list↔detail split rather than a
/// list that pushes to a full-screen editor sheet-on-a-sheet.
struct NotesTabView: View {
    @Environment(TravelNotesStore.self) private var store
    @Environment(FamilyStore.self) private var family
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @State private var editing: TravelNote?

    /// iPad/Split-View/the Duo's inner display — the same check AppShellKit uses
    /// to decide sidebar vs. tab bar.
    private var isRegularWidth: Bool {
        DuoDisplay.isInnerDisplay(horizontal: horizontalSizeClass, vertical: verticalSizeClass)
    }

    var body: some View {
        Group {
            if isRegularWidth {
                NavigationSplitView {
                    listColumn
                } detail: {
                    if let note = editing {
                        TravelNoteEditorView(note: note, embedded: true) { editing = nil }
                            // A fresh id per note so the editor's @State (title,
                            // blocks, tags) resets when the selection changes
                            // instead of carrying the previous note's draft over.
                            .id(note.id)
                    } else {
                        ContentUnavailableView(
                            "Select a note",
                            systemImage: "note.text",
                            description: Text("Choose a note from the list, or create a new one."))
                    }
                }
            } else {
                NavigationStack {
                    listColumn
                        .sheet(item: $editing) { TravelNoteEditorView(note: $0) }
                }
            }
        }
    }

    private var listColumn: some View {
        Group {
            if store.notes.isEmpty {
                ContentUnavailableView {
                    Label("No notes yet", systemImage: "note.text")
                } description: {
                    Text("Jot travel wisdom, road-trip tips, or anything worth remembering — like \u{201C}never stop in San Fernando.\u{201D}")
                } actions: {
                    Button("New note") { newNote() }.buttonStyle(.borderedProminent)
                }
            } else {
                List {
                    ForEach(store.notes) { note in
                        Button { editing = note } label: { NoteRow(note: note) }
                            .buttonStyle(.plain)
                            .listRowBackground(isRegularWidth && editing?.id == note.id
                                                ? Theme.Colors.brand.opacity(0.12) : Color.clear)
                    }
                    .onDelete { idx in
                        let items = idx.map { store.notes[$0] }
                        Task { for i in items { await store.delete(i) } }
                    }
                }
            }
        }
        .navigationTitle("Notes")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
            ToolbarItem(placement: .primaryAction) {
                Button { newNote() } label: { Image(systemName: "plus") }
            }
        }
        .refreshable { await store.load() }
    }

    private func newNote() {
        guard let fid = family.familyID else { return }
        editing = TravelNote(familyID: fid)
    }
}

private struct NoteRow: View {
    let note: TravelNote

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(note.title.nilIfBlank ?? "Untitled note").font(.headline)
            if let preview = note.preview?.nilIfBlank {
                Text(preview).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
            }
            if !note.tags.isEmpty {
                Text(note.tags.map { "#\($0)" }.joined(separator: " "))
                    .font(.caption).foregroundStyle(Theme.Colors.brand)
            }
        }
        .padding(.vertical, 2)
    }
}

struct TravelNoteEditorView: View {
    @Environment(TravelNotesStore.self) private var store
    @Environment(FamilyStore.self) private var family
    @Environment(\.dismiss) private var dismiss

    @State private var draft: TravelNote
    @State private var blocks: [ContentBlock]
    @State private var tagsText: String

    /// True when hosted inline as a NavigationSplitView detail column (regular
    /// width) rather than presented as its own sheet. Inline, there's no sheet to
    /// Cancel and no `dismiss()` to call — Save (the only exit) reports back via
    /// `onClose` so the caller can clear its selection instead.
    private var embedded: Bool
    private var onClose: (() -> Void)?

    init(note: TravelNote, embedded: Bool = false, onClose: (() -> Void)? = nil) {
        _draft = State(initialValue: note)
        _blocks = State(initialValue: note.content)
        _tagsText = State(initialValue: note.tags.joined(separator: ", "))
        self.embedded = embedded
        self.onClose = onClose
    }

    var body: some View {
        Group {
            if embedded {
                editor
            } else {
                NavigationStack { editor }
            }
        }
    }

    private var editor: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                TextField("Note title", text: $draft.title).font(.title2.bold())
                TextField("Tags (comma separated)", text: $tagsText)
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16).padding(.top, 12)
            Divider().padding(.top, 8)
            BlockDocumentEditor(blocks: $blocks)
        }
        // Readable width: a note is a text document, not a form that should
        // stretch to a 13" iPad's full width.
        .frame(maxWidth: 672)
        .frame(maxWidth: .infinity)
        .navigationTitle("Note")
        #if !targetEnvironment(macCatalyst)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            if !embedded {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
            ToolbarItem(placement: .confirmationAction) { Button("Save") { Task { await save() } } }
        }
    }

    private func save() async {
        draft.content = BlockDocumentEditor.cleaned(blocks)
        draft.tags = tagsText.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        if draft.createdBy == nil { draft.createdBy = family.currentMember?.id }
        await store.save(draft)
        if embedded { onClose?() } else { dismiss() }
    }
}

/// Rich-text notes for a single trip (fam_trips.notes_content).
struct TripNotesEditorView: View {
    let trip: Trip
    @Environment(TripsStore.self) private var trips
    @Environment(\.dismiss) private var dismiss
    @State private var blocks: [ContentBlock]

    init(trip: Trip) {
        self.trip = trip
        _blocks = State(initialValue: trip.notesContent ?? [])
    }

    var body: some View {
        BlockDocumentEditor(blocks: $blocks)
            .navigationTitle("Trip Notes")
            #if !targetEnvironment(macCatalyst)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task {
                            await trips.saveTripNotes(tripID: trip.id, blocks: BlockDocumentEditor.cleaned(blocks))
                            dismiss()
                        }
                    }
                }
            }
    }
}
