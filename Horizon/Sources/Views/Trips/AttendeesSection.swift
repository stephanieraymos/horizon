import SwiftUI
import Observation
import Supabase

/// Loads + mutates a plan's guest list with RSVP status (fam_trip_attendees).
@Observable
@MainActor
final class AttendeesStore {
    var attendees: [TripAttendee] = []

    private func fetch(_ tripID: UUID) async -> [TripAttendee] {
        (try? await supabase.from("fam_trip_attendees")
            .select().eq("trip_id", value: tripID).order("created_at").execute().value) ?? []
    }

    /// Load the guest list, seeding it from the plan's existing people (the
    /// `travelers` picked in the editor — stored as names) that don't yet have a
    /// guest row, so converting a trip → party carries those people over as invited
    /// guests. Each seed is (memberID, name): a roster member seeds by id, an ad-hoc
    /// typed-in traveler seeds by name.
    func load(tripID: UUID, familyID: UUID, seeds: [(memberID: UUID?, name: String)] = []) async {
        var rows = await fetch(tripID)
        // Seed from the plan's travelers ONLY on the first load (empty list) — a
        // one-time trip→party carry-over. Re-seeding on every visit would
        // resurrect guests the user deliberately removed (travelers persist on
        // the trip), making removal of a traveler-guest impossible.
        if rows.isEmpty, !seeds.isEmpty {
            var seededMembers = Set<UUID>()
            var seededNames = Set<String>()
            for s in seeds {
                let key = s.name.lowercased()
                if let mid = s.memberID {
                    // Skip if this person was already seeded by id OR by name
                    // (an ad-hoc traveler with the same name), so no dup rows.
                    if seededMembers.contains(mid) || seededNames.contains(key) { continue }
                } else if seededNames.contains(key) {
                    continue
                }
                _ = await add(tripID: tripID, familyID: familyID,
                              memberID: s.memberID, name: s.memberID == nil ? s.name : nil)
                if let mid = s.memberID { seededMembers.insert(mid) }
                seededNames.insert(key)
            }
            rows = await fetch(tripID)
        }
        attendees = rows
    }

    @discardableResult
    func add(tripID: UUID, familyID: UUID, memberID: UUID?, name: String?) async -> Bool {
        struct Row: Encodable {
            let trip_id: String; let family_id: String; let member_id: String?
            let name: String?; let status: String
        }
        do {
            let saved: TripAttendee = try await supabase.from("fam_trip_attendees")
                .insert(Row(trip_id: tripID.uuidString, family_id: familyID.uuidString,
                            member_id: memberID?.uuidString, name: name, status: "invited"))
                .select().single().execute().value
            attendees.append(saved)
            return true
        } catch { return false }
    }

    func setStatus(_ a: TripAttendee, _ status: RSVPStatus) async {
        struct P: Encodable { let status: String }
        do {
            try await supabase.from("fam_trip_attendees").update(P(status: status.rawValue))
                .eq("id", value: a.id).execute()
            if let i = attendees.firstIndex(where: { $0.id == a.id }) { attendees[i].status = status }
        } catch { /* non-fatal */ }
    }

    func remove(_ a: TripAttendee) async {
        do {
            try await supabase.from("fam_trip_attendees").delete().eq("id", value: a.id).execute()
            attendees.removeAll { $0.id == a.id }
        } catch { /* non-fatal */ }
    }
}

/// Guest list with invited → going/maybe/declined RSVP, for a plan detail page.
struct AttendeesSection: View {
    let tripID: UUID
    let familyID: UUID
    let peopleLabel: String
    /// The plan's existing people (trip travelers, stored as names) to seed the
    /// guest list from.
    var travelerNames: [String] = []

    @Environment(FamilyStore.self) private var family
    @State private var store = AttendeesStore()
    @State private var showAdd = false

    private func displayName(_ a: TripAttendee) -> String {
        if let mid = a.memberID, let n = family.memberName(id: mid) { return n }
        return a.name ?? "Guest"
    }
    private func avatarURL(_ a: TripAttendee) -> String? {
        a.memberID.flatMap { mid in family.members.first { $0.id == mid }?.avatarURL }
    }
    private var summary: String {
        let going = store.attendees.filter { $0.status == .going }.count
        let invited = store.attendees.count
        return "\(going) going · \(invited) invited"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(peopleLabel).font(.headline)
                Spacer()
                if !store.attendees.isEmpty {
                    Text(summary).font(.caption).foregroundStyle(.secondary)
                }
                Button { showAdd = true } label: { Image(systemName: "plus.circle.fill") }
            }

            if store.attendees.isEmpty {
                Text("No \(peopleLabel.lowercased()) yet — tap + to invite.")
                    .font(.callout).foregroundStyle(.secondary)
            } else {
                ForEach(store.attendees) { a in
                    HStack(spacing: 10) {
                        PersonAvatar(name: displayName(a), avatarURL: avatarURL(a), size: 32)
                        Text(displayName(a))
                        Spacer()
                        Menu {
                            ForEach(RSVPStatus.allCases, id: \.self) { s in
                                Button { Task { await store.setStatus(a, s) } } label: {
                                    Label(s.label, systemImage: s.systemImage)
                                }
                            }
                            Divider()
                            Button("Remove", systemImage: "trash", role: .destructive) {
                                Task { await store.remove(a) }
                            }
                        } label: {
                            Label(a.status.label, systemImage: a.status.systemImage)
                                .font(.caption.weight(.medium)).foregroundStyle(a.status.color)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .task {
            if family.members.isEmpty { await family.load() }
            // Resolve each traveler name to a shared `people` row, creating one for
            // ad-hoc names that aren't on the roster yet — so a trip→party's guests
            // all live in `people` (and appear in Glade), never as name-only rows.
            var seeds: [(memberID: UUID?, name: String)] = []
            for name in travelerNames {
                if let existing = family.members.first(where: { $0.name == name }) {
                    seeds.append((existing.id, name))
                } else if let created = await family.createMember(name: name) {
                    seeds.append((created.id, name))
                } else {
                    seeds.append((nil, name))
                }
            }
            await store.load(tripID: tripID, familyID: familyID, seeds: seeds)
        }
        .sheet(isPresented: $showAdd) {
            AddAttendeeSheet(tripID: tripID, familyID: familyID, store: store,
                             existingMemberIDs: Set(store.attendees.compactMap { $0.memberID }))
        }
    }
}

private struct AddAttendeeSheet: View {
    let tripID: UUID
    let familyID: UUID
    let store: AttendeesStore
    let existingMemberIDs: Set<UUID>

    @Environment(FamilyStore.self) private var family
    @Environment(\.dismiss) private var dismiss
    @State private var newName = ""
    @State private var query = ""

    /// People not already invited, filtered by the search field.
    private var candidates: [FamilyMember] {
        let available = family.members.filter { !existingMemberIDs.contains($0.id) }
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return available }
        return available.filter { $0.name.localizedCaseInsensitiveContains(q) }
    }

    /// Lowercased display names already on the guest list (roster members by
    /// resolved name + ad-hoc typed names), so the "invite as new" fallback never
    /// offers to add someone who's already invited (a duplicate row).
    private var invitedNames: Set<String> {
        Set(store.attendees.map { a -> String in
            let name = a.memberID.flatMap { mid in family.members.first { $0.id == mid }?.name } ?? a.name ?? ""
            return name.trimmingCharacters(in: .whitespaces).lowercased()
        })
    }

    private func addNew(_ name: String) {
        let n = name.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty else { return }
        Task {
            // Back every new guest with a real shared `people` row (via
            // FamilyStore → fam_family_members view → people) so they show up in
            // Glade — never store a name-only attendee. Fall back to name-only
            // only if the people insert fails, so the guest isn't lost.
            let member = await family.createMember(name: n)
            await store.add(tripID: tripID, familyID: familyID,
                            memberID: member?.id, name: member == nil ? n : nil)
            dismiss()
        }
    }

    var body: some View {
        NavigationStack {
            List {
                // Manual add hides while searching (the search results drive the
                // "invite as new" path instead).
                if query.trimmingCharacters(in: .whitespaces).isEmpty {
                    Section("Add someone new") {
                        HStack {
                            TextField("Name", text: $newName)
                            Button("Add") { addNew(newName) }
                                .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                        }
                    }
                }
                Section("From people") {
                    ForEach(candidates) { m in
                        Button {
                            Task { await store.add(tripID: tripID, familyID: familyID, memberID: m.id, name: m.name); dismiss() }
                        } label: {
                            HStack {
                                Text(m.name).foregroundStyle(.primary)
                                Spacer()
                                Text(m.bucketLabel).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    // No match → offer to invite the typed name as a new guest,
                    // unless that name is already on the guest list (avoid a dup).
                    if candidates.isEmpty {
                        let q = query.trimmingCharacters(in: .whitespaces)
                        if q.isEmpty {
                            Text("No people yet.").foregroundStyle(.secondary)
                        } else if invitedNames.contains(q.lowercased()) {
                            Label("“\(q)” is already invited", systemImage: "checkmark.circle")
                                .foregroundStyle(.secondary)
                        } else {
                            Button {
                                addNew(q)
                            } label: {
                                Label("Invite “\(q)” as a new guest", systemImage: "person.badge.plus")
                            }
                        }
                    }
                }
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always),
                        prompt: "Search people")
            .navigationTitle("Add Guest")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
        }
    }
}
