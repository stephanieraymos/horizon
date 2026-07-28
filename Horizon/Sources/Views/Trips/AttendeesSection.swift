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
        let haveMembers = Set(rows.compactMap { $0.memberID })
        let haveNames = Set(rows.compactMap { $0.name })
        var didSeed = false
        for s in seeds {
            if let mid = s.memberID {
                if haveMembers.contains(mid) { continue }
            } else if haveNames.contains(s.name) {
                continue
            }
            _ = await add(tripID: tripID, familyID: familyID,
                          memberID: s.memberID, name: s.memberID == nil ? s.name : nil)
            didSeed = true
        }
        if didSeed { rows = await fetch(tripID) }
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
            let seeds: [(memberID: UUID?, name: String)] = travelerNames.map { name in
                (family.members.first { $0.name == name }?.id, name)
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

    var body: some View {
        NavigationStack {
            List {
                Section("Add someone new") {
                    HStack {
                        TextField("Name", text: $newName)
                        Button("Add") {
                            let n = newName.trimmingCharacters(in: .whitespaces)
                            guard !n.isEmpty else { return }
                            Task { await store.add(tripID: tripID, familyID: familyID, memberID: nil, name: n); dismiss() }
                        }
                        .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
                Section("From people") {
                    ForEach(family.members.filter { !existingMemberIDs.contains($0.id) }) { m in
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
                }
            }
            .navigationTitle("Add Guest")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
        }
    }
}
