import Foundation
import Observation
import Supabase

/// Reusable travel-knowledge notes (fam_travel_notes), family-scoped.
@Observable
@MainActor
final class TravelNotesStore {
    var notes: [TravelNote] = []
    var errorMessage: String?

    func load() async {
        do {
            notes = try await supabase.from("fam_travel_notes")
                .select().order("updated_at", ascending: false).execute().value
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func save(_ note: TravelNote) async {
        do {
            try await supabase.from("fam_travel_notes").upsert(note).execute()
            await load()
        } catch { errorMessage = error.localizedDescription }
    }

    func delete(_ note: TravelNote) async {
        do {
            try await supabase.from("fam_travel_notes").delete().eq("id", value: note.id).execute()
            notes.removeAll { $0.id == note.id }
        } catch { errorMessage = error.localizedDescription }
    }
}
