import SwiftUI

struct NotesTabView: View {
    @Environment(TravelNotesStore.self) private var store
    @Environment(FamilyStore.self) private var family
    @State private var editing: TravelNote?

    var body: some View {
        NavigationStack {
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
                ToolbarItem(placement: .primaryAction) {
                    Button { newNote() } label: { Image(systemName: "plus") }
                }
            }
            .refreshable { await store.load() }
            .sheet(item: $editing) { TravelNoteEditorView(note: $0) }
        }
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

    init(note: TravelNote) {
        _draft = State(initialValue: note)
        _blocks = State(initialValue: note.content)
        _tagsText = State(initialValue: note.tags.joined(separator: ", "))
    }

    var body: some View {
        NavigationStack {
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
            .navigationTitle("Note")
            #if !targetEnvironment(macCatalyst)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { Task { await save() } } }
            }
        }
    }

    private func save() async {
        draft.content = BlockDocumentEditor.cleaned(blocks)
        draft.tags = tagsText.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        if draft.createdBy == nil { draft.createdBy = family.currentMember?.id }
        await store.save(draft)
        dismiss()
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
