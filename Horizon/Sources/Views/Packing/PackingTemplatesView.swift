import SwiftUI

/// Manage reusable packing templates: create, rename, edit items, delete.
struct PackingTemplatesView: View {
    @Environment(PackingTemplatesStore.self) private var store
    @Environment(FamilyStore.self) private var family
    @Environment(\.dismiss) private var dismiss

    @State private var creating = false
    @State private var newName = ""
    @State private var newIcon = "suitcase.fill"
    @State private var showIconPicker = false

    var body: some View {
        NavigationStack {
            List {
                if store.templates.isEmpty {
                    ContentUnavailableView("No templates yet", systemImage: "suitcase",
                        description: Text("Create a reusable list — Beach, Disneyland, camping — and apply it to any trip."))
                } else {
                    ForEach(store.templates) { template in
                        NavigationLink {
                            TemplateDetailView(template: template)
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: template.icon)
                                    .foregroundStyle(Theme.Colors.brand).frame(width: 28)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(template.name).font(.headline)
                                    Text("\(store.items(for: template.id).count) items")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                Task { await store.deleteTemplate(template) }
                            } label: { Label("Delete", systemImage: "trash") }
                        }
                    }
                }
            }
            .navigationTitle("Packing Templates")
            #if !targetEnvironment(macCatalyst)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    Button { newName = ""; newIcon = "suitcase.fill"; creating = true } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .task { if store.templates.isEmpty { await store.load() } }
            .alert("New Template", isPresented: $creating) {
                TextField("Name (e.g. Beach)", text: $newName)
                Button("Create") {
                    guard let fid = family.familyID else { return }
                    Task { await store.createTemplate(familyID: fid, name: newName, icon: newIcon,
                                                      createdBy: family.currentMember?.userID) }
                }
                Button("Cancel", role: .cancel) {}
            }
        }
    }
}

/// Edit one template's items (add / remove).
struct TemplateDetailView: View {
    let template: PackingTemplate
    @Environment(PackingTemplatesStore.self) private var store
    @Environment(TripsStore.self) private var trips

    @State private var newItem = ""
    @State private var newCategory = ""

    var body: some View {
        List {
            Section {
                ForEach(store.items(for: template.id)) { item in
                    HStack(spacing: 10) {
                        Image(systemName: trips.icon(forCategory: item.category))
                            .foregroundStyle(.secondary).frame(width: 22)
                        Text(item.item)
                        Spacer()
                        if let cat = item.category?.nilIfBlank {
                            Text(cat).font(.caption).foregroundStyle(.tertiary)
                        }
                    }
                }
                .onDelete { idxSet in
                    let items = store.items(for: template.id)
                    for i in idxSet { Task { await store.deleteItem(items[i]) } }
                }
            } header: { Text("Items") }

            Section("Add item") {
                TextField("Item", text: $newItem)
                ComboField(
                    placeholder: "Category (optional)",
                    text: $newCategory,
                    options: trips.packingCategories.map { .init(id: $0.id.uuidString, name: $0.name, icon: $0.icon) },
                    onPick: { newCategory = $0.name })
                Button("Add") {
                    Task {
                        await store.addItem(templateID: template.id, item: newItem, category: newCategory.nilIfBlank)
                        newItem = ""; newCategory = ""
                    }
                }
                .disabled(newItem.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .navigationTitle(template.name)
        #if !targetEnvironment(macCatalyst)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}

/// Apply a template to the current trip for chosen travelers.
struct ApplyTemplateSheet: View {
    let store: TripDetailStore
    let travelerNames: [String]

    @Environment(PackingTemplatesStore.self) private var templates
    @Environment(FamilyStore.self) private var family
    @Environment(\.dismiss) private var dismiss

    @State private var selectedTemplate: PackingTemplate?
    @State private var selectedMembers: Set<UUID> = []
    @State private var isApplying = false
    @State private var manageTemplates = false

    /// Family members who are on this trip (fallback: everyone).
    private var eligibleMembers: [FamilyMember] {
        let names = Set(travelerNames.map { $0.lowercased() })
        let onTrip = family.members.filter { names.contains($0.name.lowercased()) }
        return onTrip.isEmpty ? family.members : onTrip
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Template") {
                    if templates.templates.isEmpty {
                        Text("No templates yet.").foregroundStyle(.secondary)
                    }
                    ForEach(templates.templates) { t in
                        Button {
                            selectedTemplate = t
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: t.icon).foregroundStyle(Theme.Colors.brand).frame(width: 24)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(t.name).foregroundStyle(.primary)
                                    Text("\(templates.items(for: t.id).count) items")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if selectedTemplate?.id == t.id {
                                    Image(systemName: "checkmark").foregroundStyle(Theme.Colors.brand)
                                }
                            }
                        }
                    }
                    Button("Manage templates…") { manageTemplates = true }
                        .font(.subheadline)
                }

                Section("Add to") {
                    ForEach(eligibleMembers) { m in
                        Button {
                            if selectedMembers.contains(m.id) { selectedMembers.remove(m.id) }
                            else { selectedMembers.insert(m.id) }
                        } label: {
                            HStack {
                                PersonAvatar(name: m.name, avatarURL: m.avatarURL, size: 26)
                                Text(m.name).foregroundStyle(.primary)
                                Spacer()
                                if selectedMembers.contains(m.id) {
                                    Image(systemName: "checkmark").foregroundStyle(Theme.Colors.brand)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Apply Template")
            #if !targetEnvironment(macCatalyst)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await apply() }
                    } label: { if isApplying { ProgressView() } else { Text("Apply") } }
                    .disabled(isApplying || selectedTemplate == nil || selectedMembers.isEmpty)
                }
            }
            .task {
                if templates.templates.isEmpty { await templates.load() }
                if family.members.isEmpty { await family.load() }
                // Pre-select everyone on the trip.
                selectedMembers = Set(eligibleMembers.map(\.id))
            }
            .sheet(isPresented: $manageTemplates) { PackingTemplatesView() }
        }
    }

    private func apply() async {
        guard let template = selectedTemplate else { return }
        isApplying = true
        let items = templates.items(for: template.id).map { (item: $0.item, category: $0.category) }
        await store.applyTemplate(items: items, to: Array(selectedMembers))
        isApplying = false
        dismiss()
    }
}

/// Prompts for a name, then saves the trip's current packing list as a template.
struct SaveAsTemplateSheet: View {
    let packing: [PackingItem]

    @Environment(PackingTemplatesStore.self) private var templates
    @Environment(FamilyStore.self) private var family
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var isSaving = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Template name", text: $name)
                } footer: {
                    Text("Saves \(uniqueCount) unique item\(uniqueCount == 1 ? "" : "s") from this trip as a reusable template.")
                }
            }
            .navigationTitle("Save as Template")
            #if !targetEnvironment(macCatalyst)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await save() }
                    } label: { if isSaving { ProgressView() } else { Text("Save") } }
                    .disabled(isSaving || name.trimmingCharacters(in: .whitespaces).isEmpty || packing.isEmpty)
                }
            }
        }
    }

    private var uniqueCount: Int {
        Set(packing.map { $0.item.lowercased() }).count
    }

    private func save() async {
        guard let fid = family.familyID else { return }
        isSaving = true
        await templates.createTemplate(fromPacking: packing, familyID: fid, name: name,
                                       icon: "suitcase.fill", createdBy: family.currentMember?.userID)
        isSaving = false
        dismiss()
    }
}
