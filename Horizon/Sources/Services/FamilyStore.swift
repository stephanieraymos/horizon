import Foundation
import Observation
import Supabase

/// Resolves the signed-in user's family member row (for `family_id` scoping) and
/// the full roster (for traveler pickers). Shares `fam_family_members` with
/// TheGlade and Orbit on the same backend.
@Observable
@MainActor
final class FamilyStore {
    var currentMember: FamilyMember?
    var members: [FamilyMember] = []

    var familyID: UUID? { currentMember?.familyID }

    func load() async {
        guard let userID = try? await supabase.auth.session.user.id else {
            currentMember = nil; members = []; return
        }
        do {
            currentMember = try await supabase
                .from("fam_family_members")
                .select()
                .eq("user_id", value: userID)
                .limit(1)
                .single()
                .execute()
                .value
        } catch {
            currentMember = nil
        }

        guard let familyID else { members = []; return }
        do {
            members = try await supabase
                .from("fam_family_members")
                .select()
                .eq("family_id", value: familyID)
                .order("name")
                .execute()
                .value
        } catch {
            members = []
        }
    }

    func memberName(id: UUID) -> String? {
        members.first { $0.id == id }?.name
    }
}
