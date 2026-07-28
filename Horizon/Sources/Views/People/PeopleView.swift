import SwiftUI

/// Manage everyone in the family's `people` roster: grouped by bucket, editable
/// bucket per person, and person↔person relationships. Providers (doctors) are
/// excluded by the underlying view.
struct PeopleView: View {
    @Environment(FamilyStore.self) private var family
    @State private var showAdd = false

    var body: some View {
        List {
            ForEach(family.buckets, id: \.self) { bucket in
                let people = family.members(inBucket: bucket)
                if !people.isEmpty {
                    Section(bucket.capitalized) {
                        ForEach(people) { person in
                            NavigationLink { PersonDetailView(person: person) } label: {
                                personRow(person)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("People")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showAdd = true } label: { Image(systemName: "plus") }
            }
        }
        .sheet(isPresented: $showAdd) { AddPersonSheet() }
        .task {
            if family.members.isEmpty { await family.load() }
            await family.loadRelationships()
        }
        .refreshable { await family.load(); await family.loadRelationships() }
    }

    @ViewBuilder
    private func personRow(_ person: FamilyMember) -> some View {
        HStack {
            Text(person.name)
            Spacer()
            if let first = family.relationships(for: person.id).first {
                Text("\(first.label) \(first.other.name)")
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
        }
    }
}

// MARK: - Person detail

struct PersonDetailView: View {
    let person: FamilyMember
    @Environment(FamilyStore.self) private var family
    @State private var newBucket = ""
    @State private var showNewBucket = false
    @State private var showAddRel = false

    private var current: FamilyMember { family.members.first { $0.id == person.id } ?? person }

    var body: some View {
        List {
            Section("Bucket") {
                Menu {
                    ForEach(family.buckets, id: \.self) { b in
                        Button(b.capitalized) { Task { await family.setBucket(person.id, to: b) } }
                    }
                    Divider()
                    Button("New bucket…") { showNewBucket = true }
                } label: {
                    LabeledContent("Bucket", value: current.bucketLabel)
                }
            }

            Section("Relationships") {
                let rels = family.relationships.filter { $0.fromPerson == person.id || $0.toPerson == person.id }
                if rels.isEmpty {
                    Text("No relationships yet.").foregroundStyle(.secondary).font(.callout)
                }
                ForEach(rels) { r in
                    let otherID = r.fromPerson == person.id ? r.toPerson : r.fromPerson
                    let other = family.members.first { $0.id == otherID }?.name ?? "someone"
                    Text(r.fromPerson == person.id ? "\(r.label) of \(other)" : "\(other) is \(r.label)")
                }
                .onDelete { idx in
                    let ids = idx.map { rels[$0].id }
                    Task { for id in ids { await family.deleteRelationship(id) } }
                }
                Button { showAddRel = true } label: { Label("Add relationship", systemImage: "person.2.fill") }
            }
        }
        .navigationTitle(current.name)
        .navigationBarTitleDisplayMode(.inline)
        .alert("New bucket", isPresented: $showNewBucket) {
            TextField("Bucket name", text: $newBucket)
            Button("Cancel", role: .cancel) { newBucket = "" }
            Button("Set") { let b = newBucket; newBucket = ""; Task { await family.setBucket(person.id, to: b) } }
        }
        .sheet(isPresented: $showAddRel) { AddRelationshipSheet(person: person) }
    }
}

// MARK: - Add person / relationship

struct AddPersonSheet: View {
    @Environment(FamilyStore.self) private var family
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var bucket = "friend"

    private var options: [String] {
        var s = ["friend", "household", "extended", "coworker"]
        for b in family.buckets where !s.contains(b) { s.append(b) }
        return s
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Name", text: $name)
                Picker("Bucket", selection: $bucket) {
                    ForEach(options, id: \.self) { Text($0.capitalized).tag($0) }
                }
            }
            .navigationTitle("New Person")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        Task {
                            if let m = await family.createMember(name: name) {
                                await family.setBucket(m.id, to: bucket)
                            }
                            dismiss()
                        }
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}

struct AddRelationshipSheet: View {
    let person: FamilyMember
    @Environment(FamilyStore.self) private var family
    @Environment(\.dismiss) private var dismiss
    @State private var otherID: UUID?
    @State private var label = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Relationship (mom, friend, sibling…)", text: $label)
                } footer: {
                    Text("Reads as “\(person.name) is <relationship> of <person>.”")
                }
                Picker("Of", selection: $otherID) {
                    Text("—").tag(UUID?.none)
                    ForEach(family.members.filter { $0.id != person.id }) { m in
                        Text(m.name).tag(Optional(m.id))
                    }
                }
            }
            .navigationTitle("\(person.name) is…")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        guard let otherID else { return }
                        Task { await family.addRelationship(from: person.id, to: otherID, label: label); dismiss() }
                    }
                    .disabled(otherID == nil || label.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}
