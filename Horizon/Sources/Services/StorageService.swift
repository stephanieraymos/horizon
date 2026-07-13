import Foundation
import Supabase

/// Thin wrapper over the private `trip-docs` Storage bucket. Uploads set a long
/// cache-control so objects are cacheable; see CachedStorageImage for the
/// egress-safe read path (bytes cached by storage path, not by rotating URL).
enum StorageService {
    static let bucket = "trip-docs"

    static func upload(path: String, data: Data, contentType: String) async throws {
        try await supabase.storage.from(bucket).upload(
            path,
            data: data,
            options: FileOptions(cacheControl: "31536000", contentType: contentType, upsert: true)
        )
    }

    static func signedURL(path: String, expiresIn: Int = 3600) async throws -> URL {
        try await supabase.storage.from(bucket).createSignedURL(path: path, expiresIn: expiresIn)
    }

    static func remove(path: String) async throws {
        _ = try await supabase.storage.from(bucket).remove(paths: [path])
    }
}
