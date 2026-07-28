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

    /// Synthetic, never-persisted birthday events derived from members' birthdays.
    /// Shared by the Home tab and the Countdown board so the synthesis lives in one
    /// place (id == member.id keeps them stable and member-scoped).
    var birthdayEvents: [FamilyEvent] {
        guard let familyID = members.first?.familyID else { return [] }
        return members.compactMap { m in
            guard let b = m.birthday else { return nil }
            return FamilyEvent(id: m.id, familyID: familyID, title: "\(m.name)'s Birthday",
                               eventType: FamilyEventType.birthday.rawValue, eventDate: b,
                               isAnnual: true, emoji: "🎂")
        }
    }

    /// Resolve a member by their auth user id (todos record `created_by` as a
    /// user id, not a member id).
    func memberName(userID: UUID) -> String? {
        members.first { $0.userID == userID }?.name
    }

    // MARK: - People management (buckets + relationships)

    var relationships: [PersonRelationship] = []

    /// Distinct buckets present on the roster, common ones first, then the rest.
    var buckets: [String] {
        let present = Set(members.compactMap { $0.householdType?.nilIfBlank })
        let common = ["household", "extended", "friend", "coworker", "provider"]
        let ordered = common.filter(present.contains)
        return ordered + present.subtracting(ordered).sorted()
    }

    func members(inBucket bucket: String) -> [FamilyMember] {
        members.filter { ($0.householdType ?? "household") == bucket }
    }

    func loadRelationships() async {
        guard let familyID else { relationships = []; return }
        relationships = (try? await supabase.from("people_relationships")
            .select().eq("family_id", value: familyID).execute().value) ?? []
    }

    /// Change a person's bucket (household_type). Editable, and new bucket names
    /// are allowed — it's freeform text.
    func setBucket(_ personID: UUID, to bucket: String) async {
        let trimmed = bucket.trimmingCharacters(in: .whitespaces).lowercased()
        // 'provider' is the medical directory (excluded from the fam_family_members
        // view). Setting it here would silently expel the person from Horizon into
        // Glade's provider list with no way back — reserve it.
        guard !trimmed.isEmpty, trimmed != "provider" else { return }
        struct Patch: Encodable { let household_type: String }
        do {
            try await supabase.from("fam_family_members")
                .update(Patch(household_type: trimmed)).eq("id", value: personID).execute()
            if let i = members.firstIndex(where: { $0.id == personID }) {
                members[i].householdType = trimmed
            }
        } catch { /* non-fatal */ }
    }

    /// Relationships involving a person, in both directions, as a readable phrase
    /// plus the other person. A row "X is L of Y": on X's card → "L of Y"; on Y's
    /// card → "X is L".
    func relationships(for personID: UUID) -> [(text: String, other: FamilyMember)] {
        var out: [(String, FamilyMember)] = []
        for r in relationships {
            if r.fromPerson == personID, let m = members.first(where: { $0.id == r.toPerson }) {
                out.append(("\(r.label) of \(m.name)", m))
            } else if r.toPerson == personID, let m = members.first(where: { $0.id == r.fromPerson }) {
                out.append(("\(m.name) is \(r.label)", m))
            }
        }
        return out
    }

    @discardableResult
    func addRelationship(from: UUID, to: UUID, label: String) async -> Bool {
        guard let familyID, from != to else { return false }
        let trimmed = label.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return false }
        struct Row: Encodable { let family_id: String; let from_person: String; let to_person: String; let label: String }
        do {
            let saved: PersonRelationship = try await supabase.from("people_relationships")
                .insert(Row(family_id: familyID.uuidString, from_person: from.uuidString,
                            to_person: to.uuidString, label: trimmed))
                .select().single().execute().value
            relationships.append(saved)
            return true
        } catch { return false }
    }

    func deleteRelationship(_ id: UUID) async {
        do {
            try await supabase.from("people_relationships").delete().eq("id", value: id).execute()
            relationships.removeAll { $0.id == id }
        } catch { /* non-fatal */ }
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
        // Default a newly-added person to a neutral "friend" bucket, NOT the
        // underlying table's 'household' default — otherwise every guest added to
        // a trip/party gets promoted to immediate family. The bucket is editable
        // later in People management.
        struct NewMember: Encodable {
            let family_id: String; let name: String; let role: String; let household_type: String
        }
        do {
            let row: FamilyMember = try await supabase
                .from("fam_family_members")
                .insert(NewMember(family_id: familyID.uuidString, name: trimmed,
                                  role: "none", household_type: "friend"))
                .select().single().execute().value
            members.append(row)
            members.sort { $0.name < $1.name }
            return row
        } catch {
            return nil
        }
    }
}
