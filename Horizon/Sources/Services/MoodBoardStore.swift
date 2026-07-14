import Foundation
import Observation
import Supabase

/// Backs a trip's mood board. Reuses the shared `fam_albums` (one album per
/// trip, linked via `trip_id`) and `fam_memories` tables, uploading photos to
/// the public `fam-memories` Storage bucket. Each Horizon upload is one memory
/// row (single URL) so `tag` + `addedBy` filter per-photo.
@Observable
@MainActor
final class MoodBoardStore {
    private(set) var album: Album?
    private(set) var photos: [MoodPhoto] = []
    private(set) var isLoading = false
    var isUploading = false
    var error: String?

    private let bucketID = "fam-memories"

    /// Distinct tags present, sorted, for the filter bar.
    var tags: [String] {
        var seen = Set<String>()
        var out: [String] = []
        for p in photos {
            if let t = p.tag?.nilIfBlank, !seen.contains(t.lowercased()) {
                seen.insert(t.lowercased()); out.append(t)
            }
        }
        return out.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    /// Distinct uploader ids present, for the filter bar.
    var uploaderIDs: [UUID] {
        var seen = Set<UUID>()
        var out: [UUID] = []
        for p in photos {
            if let a = p.addedBy, !seen.contains(a) { seen.insert(a); out.append(a) }
        }
        return out
    }

    // MARK: - Load

    /// Finds (or creates) the album for this trip and loads its photos.
    func load(tripID: UUID, familyID: UUID, tripName: String, createdBy: UUID?) async {
        isLoading = true
        defer { isLoading = false }
        do {
            let existing: [Album] = try await supabase
                .from("fam_albums")
                .select()
                .eq("trip_id", value: tripID)
                .order("created_at", ascending: true)
                .limit(1)
                .execute()
                .value
            if let a = existing.first {
                album = a
            } else {
                // Lazily create the trip's album on first open.
                let fresh = Album(familyID: familyID, name: tripName, tripID: tripID, createdBy: createdBy)
                let saved: Album = try await supabase
                    .from("fam_albums").insert(fresh).select().single().execute().value
                album = saved
            }
        } catch {
            self.error = error.localizedDescription
            return
        }
        await loadPhotos()
    }

    private func loadPhotos() async {
        guard let albumID = album?.id else { return }
        do {
            let rows: [Memory] = try await supabase
                .from("fam_memories")
                .select()
                .eq("album_id", value: albumID)
                .order("created_at", ascending: false)
                .execute()
                .value
            photos = rows.flatMap { mem in
                mem.photoURLs.enumerated().map { idx, url in
                    MoodPhoto(id: "\(mem.id.uuidString)-\(idx)", url: url, tag: mem.tag,
                              addedBy: mem.addedBy, memoryID: mem.id, caption: mem.caption)
                }
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    // MARK: - Add

    /// Uploads JPEGs (each as its own memory row) tagged + attributed to the
    /// uploader. Returns the number successfully added.
    @discardableResult
    func addPhotos(_ jpegPayloads: [Data], tag: String?, caption: String?,
                   familyID: UUID, addedBy: UUID?) async -> Int {
        guard let albumID = album?.id, !jpegPayloads.isEmpty else { return 0 }
        isUploading = true
        defer { isUploading = false }
        let bucket = supabase.storage.from(bucketID)
        var added = 0

        for data in jpegPayloads {
            let memoryID = UUID()
            // Lowercased path segments: the fam-memories storage RLS compares the
            // family-id segment against a lowercase uuid.
            let path = "\(familyID.uuidString.lowercased())/\(memoryID.uuidString.lowercased())/\(UUID().uuidString.lowercased()).jpg"
            do {
                _ = try await bucket.upload(path, data: data,
                                            options: .init(contentType: "image/jpeg", upsert: false))
                let publicURL = try bucket.getPublicURL(path: path).absoluteString
                let memory = Memory(
                    id: memoryID, familyID: familyID, albumID: albumID,
                    caption: caption?.nilIfBlank, photoURLs: [publicURL],
                    takenAt: nil, location: nil, addedBy: addedBy,
                    tag: tag?.nilIfBlank, createdAt: Date())
                let saved: Memory = try await supabase
                    .from("fam_memories").insert(memory).select().single().execute().value
                let items = saved.photoURLs.enumerated().map { idx, url in
                    MoodPhoto(id: "\(saved.id.uuidString)-\(idx)", url: url, tag: saved.tag,
                              addedBy: saved.addedBy, memoryID: saved.id, caption: saved.caption)
                }
                photos.insert(contentsOf: items, at: 0)
                added += 1

                // Promote first photo to album cover if none set yet.
                if var a = album, a.coverPhotoURL == nil {
                    a.coverPhotoURL = publicURL
                    if (try? await supabase.from("fam_albums")
                        .update(["cover_photo_url": publicURL]).eq("id", value: a.id).execute()) != nil {
                        album = a
                    }
                }
            } catch {
                self.error = "Photo upload failed: \(error.localizedDescription)"
            }
        }
        return added
    }

    // MARK: - Delete

    /// Deletes the memory row backing a photo and best-effort removes its
    /// storage objects.
    func delete(_ photo: MoodPhoto) async {
        do {
            try await supabase.from("fam_memories").delete().eq("id", value: photo.memoryID).execute()
            photos.removeAll { $0.memoryID == photo.memoryID }
            for p in [photo] {
                if let path = storagePath(from: p.url) {
                    _ = try? await supabase.storage.from(bucketID).remove(paths: [path])
                }
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// Converts a Supabase public URL back to its storage object path.
    private func storagePath(from publicURL: String) -> String? {
        let marker = "/storage/v1/object/public/\(bucketID)/"
        guard let range = publicURL.range(of: marker) else { return nil }
        return String(publicURL[range.upperBound...])
    }
}
