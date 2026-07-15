import SwiftUI

struct EventEditView: View {
    let existing: FamilyEvent?
    /// Seed a NEW event (existing == nil) from a tapped countdown.
    var prefillTitle: String? = nil
    var prefillDate: Date? = nil

    @Environment(EventsStore.self) private var events
    @Environment(FamilyStore.self) private var family
    @Environment(\.dismiss) private var dismiss

    @State private var title: String = ""
    @State private var eventType: String = FamilyEventType.vacation.rawValue
    @State private var eventDate: Date = Calendar.current.date(byAdding: .day, value: 14, to: Date()) ?? Date()
    @State private var isAnnual: Bool = false
    @State private var description: String = ""
    @State private var emoji: String = ""
    @State private var selectedMembers: Set<String> = []
    @State private var isSaving = false

    private var navTitle: String { existing == nil ? "New Date" : "Edit Date" }

    /// Whether the selected type auto-repeats every year (birthday / anniversary).
    private var isAnnualType: Bool {
        FamilyEventType.annualTypes.contains(eventType)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Event") {
                    TextField("What's the event?", text: $title)
                    Picker("Type", selection: $eventType) {
                        ForEach(FamilyEventType.allCases, id: \.self) { t in
                            Text(t.rawValue).tag(t.rawValue)
                        }
                    }
                    .onChange(of: eventType) { _, newType in
                        // Auto-enable is_annual for birthday / anniversary
                        if FamilyEventType.annualTypes.contains(newType) {
                            isAnnual = true
                        }
                    }
                    TextField("Emoji (optional)", text: $emoji)
                        .textInputAutocapitalization(.never)
                }

                Section {
                    // Show full date (including year) so birthdays can capture birth year
                    DatePicker("Date", selection: $eventDate, displayedComponents: .date)
                    Toggle("Repeats every year", isOn: $isAnnual)
                } header: {
                    Text("When")
                } footer: {
                    if isAnnual {
                        if isAnnualType {
                            Text("The event date's year is used to calculate ages / anniversaries. The countdown always shows the next upcoming occurrence.")
                        } else {
                            Text("The countdown will always show the next upcoming occurrence of this date.")
                        }
                    }
                }

                Section("Who's involved") {
                    if family.members.isEmpty {
                        Text("No family members loaded").foregroundStyle(.secondary)
                    } else {
                        ForEach(family.members.filter { $0.role != .none }) { member in
                            Toggle(member.name, isOn: Binding(
                                get: { selectedMembers.contains(member.name) },
                                set: { isOn in
                                    if isOn { selectedMembers.insert(member.name) }
                                    else { selectedMembers.remove(member.name) }
                                }
                            ))
                        }
                    }
                }

                Section("Description") {
                    TextField("Add details", text: $description, axis: .vertical)
                        .lineLimit(2...6)
                }

                if existing != nil {
                    Section {
                        Button("Delete date", role: .destructive) {
                            if let existing {
                                Task {
                                    await events.delete(existing)
                                    dismiss()
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle(navTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await save() }
                    } label: {
                        if isSaving { ProgressView() } else { Text("Save") }
                    }
                    .disabled(isSaving || title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .onAppear { prefill() }
    }

    private func prefill() {
        if family.members.isEmpty {
            Task { await family.load() }
        }
        guard let existing else {
            if let prefillTitle { title = prefillTitle }
            if let prefillDate { eventDate = prefillDate }
            return
        }
        title           = existing.title
        eventType       = existing.eventType ?? FamilyEventType.vacation.rawValue
        eventDate       = existing.eventDate
        isAnnual        = existing.isAnnual
        description     = existing.description ?? ""
        emoji           = existing.emoji ?? ""
        selectedMembers = Set(existing.members ?? [])
    }

    private func save() async {
        guard let familyID = family.familyID else { return }
        isSaving = true
        let ok = await events.upsert(
            id: existing?.id,
            familyID: familyID,
            title: title.trimmingCharacters(in: .whitespaces),
            eventType: eventType,
            eventDate: eventDate,
            isAnnual: isAnnual,
            description: description,
            emoji: emoji,
            members: selectedMembers.isEmpty ? nil : Array(selectedMembers).sorted(),
            tripID: existing?.tripID,
            createdBy: existing?.createdBy ?? family.currentMember?.userID
        )
        isSaving = false
        if ok { dismiss() }
    }
}
