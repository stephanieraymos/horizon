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

    /// Creates a lightweight person (role=none) so they're reusable on future
    /// trips. Returns the created member, or an existing one with the same name.
    @discardableResult
    func createMember(name: String) async -> FamilyMember? {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, let familyID else { return nil }
        if let existing = members.first(where: { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }) {
            return existing
        }
        struct NewMember: Encodable { let family_id: String; let name: String; let role: String }
        do {
            let row: FamilyMember = try await supabase
                .from("fam_family_members")
                .insert(NewMember(family_id: familyID.uuidString, name: trimmed, role: "none"))
                .select().single().execute().value
            members.append(row)
            members.sort { $0.name < $1.name }
            return row
        } catch {
            return nil
        }
    }
}
