import Foundation
import Observation
import Supabase

/// Loads and persists per-member travel documents (`fam_traveler_profiles`).
@Observable
@MainActor
final class TravelerProfilesStore {
    private(set) var profiles: [TravelerProfile] = []
    var error: String?

    func load() async {
        do {
            profiles = try await supabase.from("fam_traveler_profiles").select().execute().value
        } catch { self.error = error.localizedDescription }
    }

    func profile(for memberID: UUID) -> TravelerProfile? {
        profiles.first { $0.memberID == memberID }
    }

    func save(_ profile: TravelerProfile) async {
        do {
            let saved: TravelerProfile = try await supabase.from("fam_traveler_profiles")
                .upsert(profile, onConflict: "member_id").select().single().execute().value
            if let i = profiles.firstIndex(where: { $0.memberID == saved.memberID }) { profiles[i] = saved }
            else { profiles.append(saved) }
        } catch { self.error = error.localizedDescription }
    }
}
