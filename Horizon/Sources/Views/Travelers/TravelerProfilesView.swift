import SwiftUI

/// Lists family members and their saved travel documents; tap to edit.
struct TravelerProfilesView: View {
    @Environment(TravelerProfilesStore.self) private var store
    @Environment(FamilyStore.self) private var family
    @Environment(\.dismiss) private var dismiss

    @State private var editingMember: FamilyMember?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(family.members) { member in
                        Button { editingMember = member } label: {
                            HStack(spacing: 12) {
                                PersonAvatar(name: member.name, avatarURL: member.avatarURL, size: 34)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(member.name).font(.headline)
                                    Text(summary(for: member)).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                            }
                        }
                    }
                } footer: {
                    Text("Passport numbers and IDs are stored privately in your family backend and visible only to your family.")
                }
            }
            .navigationTitle("Travelers")
            #if !targetEnvironment(macCatalyst)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .task {
                if family.members.isEmpty { await family.load() }
                if store.profiles.isEmpty { await store.load() }
            }
            .sheet(item: $editingMember) { member in
                TravelerProfileEditView(member: member)
            }
        }
    }

    private func summary(for member: FamilyMember) -> String {
        guard let p = store.profile(for: member.id) else { return "No documents saved" }
        var parts: [String] = []
        if p.passportNumber?.nilIfBlank != nil { parts.append("Passport") }
        if p.knownTravelerNumber?.nilIfBlank != nil { parts.append("Known Traveler") }
        if !p.loyaltyPrograms.isEmpty { parts.append("\(p.loyaltyPrograms.count) loyalty") }
        return parts.isEmpty ? "No documents saved" : parts.joined(separator: " · ")
    }
}

struct TravelerProfileEditView: View {
    let member: FamilyMember
    @Environment(TravelerProfilesStore.self) private var store
    @Environment(FamilyStore.self) private var family
    @Environment(\.dismiss) private var dismiss

    @State private var passportNumber = ""
    @State private var hasExpiry = false
    @State private var passportExpiry = Date()
    @State private var knownTraveler = ""
    @State private var loyalty: [LoyaltyProgram] = []
    @State private var notes = ""
    @State private var newProgram = ""
    @State private var newNumber = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Passport") {
                    TextField("Passport number", text: $passportNumber)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                    Toggle("Expiry date", isOn: $hasExpiry)
                    if hasExpiry {
                        DatePicker("Expires", selection: $passportExpiry, displayedComponents: .date)
                    }
                }
                Section("Known Traveler / TSA") {
                    TextField("KTN / Global Entry / TSA PreCheck", text: $knownTraveler)
                        .autocorrectionDisabled()
                }
                Section("Loyalty programs") {
                    ForEach(loyalty) { p in
                        HStack {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(p.program).font(.subheadline)
                                Text(p.number).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                    }
                    .onDelete { loyalty.remove(atOffsets: $0) }
                    HStack {
                        TextField("Program", text: $newProgram)
                        TextField("Number", text: $newNumber).autocorrectionDisabled()
                        Button {
                            let prog = newProgram.trimmingCharacters(in: .whitespaces)
                            let num = newNumber.trimmingCharacters(in: .whitespaces)
                            guard !prog.isEmpty, !num.isEmpty else { return }
                            loyalty.append(LoyaltyProgram(program: prog, number: num))
                            newProgram = ""; newNumber = ""
                        } label: { Image(systemName: "plus.circle.fill") }
                        .disabled(newProgram.trimmingCharacters(in: .whitespaces).isEmpty
                                  || newNumber.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
                Section("Notes") {
                    TextField("Anything else (visa, TSA notes)", text: $notes, axis: .vertical).lineLimit(2...5)
                }
            }
            .navigationTitle(member.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await save() } }
                }
            }
            .onAppear(perform: prefill)
        }
    }

    private func prefill() {
        guard let p = store.profile(for: member.id) else { return }
        passportNumber = p.passportNumber ?? ""
        if let e = p.passportExpiry { hasExpiry = true; passportExpiry = e }
        knownTraveler = p.knownTravelerNumber ?? ""
        loyalty = p.loyaltyPrograms
        notes = p.notes ?? ""
    }

    private func save() async {
        guard let familyID = family.familyID else { return }
        let existing = store.profile(for: member.id)
        let profile = TravelerProfile(
            id: existing?.id ?? UUID(),
            familyID: familyID,
            memberID: member.id,
            passportNumber: passportNumber.nilIfBlank,
            passportExpiry: hasExpiry ? passportExpiry : nil,
            knownTravelerNumber: knownTraveler.nilIfBlank,
            loyaltyPrograms: loyalty,
            notes: notes.nilIfBlank)
        await store.save(profile)
        dismiss()
    }
}
