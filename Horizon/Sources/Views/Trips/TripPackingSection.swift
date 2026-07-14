import SwiftUI

struct TripPackingSection: View {
    let store: TripDetailStore
    var travelerNames: [String] = []
    @Environment(FamilyStore.self) private var family
    @Environment(TripsStore.self) private var trips
    @State private var grouping: Grouping = .person
    @State private var showAdd = false
    @State private var showManageCategories = false
    @State private var showApplyTemplate = false
    @State private var showSaveTemplate = false

    enum Grouping: String, CaseIterable { case person = "Person", category = "Category" }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Packing").font(.title3.bold())
                Spacer()
                Menu {
                    Button("Add item", systemImage: "plus") { showAdd = true }
                    Button("Apply template", systemImage: "suitcase") { showApplyTemplate = true }
                    if !store.packing.isEmpty {
                        Button("Save list as template", systemImage: "square.and.arrow.down") { showSaveTemplate = true }
                    }
                    Button("Manage categories", systemImage: "tag") { showManageCategories = true }
                } label: { Image(systemName: "plus.circle.fill").font(.title3) }
                    .tint(Theme.Colors.brand)
            }

            if store.packing.isEmpty {
                Text("Nothing packed yet. Add items per person and category.")
                    .font(.callout).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding().background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 12))
            } else {
                Picker("Group by", selection: $grouping) {
                    ForEach(Grouping.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)

                ForEach(groups, id: \.title) { group in
                    VStack(alignment: .leading, spacing: 4) {
                        Label(group.title, systemImage: group.icon)
                            .font(.subheadline.bold()).foregroundStyle(.secondary)
                        ForEach(group.items) { item in
                            PackingRow(item: item, icon: trips.icon(forCategory: item.category)) {
                                Task { await store.togglePacking(item) }
                            }
                            .contextMenu {
                                Button("Delete", role: .destructive) { Task { await store.deletePacking(item) } }
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .sheet(isPresented: $showAdd) { PackingAddView(store: store) }
        .sheet(isPresented: $showManageCategories) { ManageCategoriesView() }
        .sheet(isPresented: $showApplyTemplate) {
            ApplyTemplateSheet(store: store, travelerNames: travelerNames)
        }
        .sheet(isPresented: $showSaveTemplate) {
            SaveAsTemplateSheet(packing: store.packing)
        }
    }

    private var groups: [(title: String, icon: String, items: [PackingItem])] {
        switch grouping {
        case .person:
            return Dictionary(grouping: store.packing, by: \.memberID)
                .map { (family.memberName(id: $0.key) ?? "Someone", "person.circle", $0.value.sorted { $0.item < $1.item }) }
                .sorted { $0.0 < $1.0 }
                .map { (title: $0.0, icon: $0.1, items: $0.2) }
        case .category:
            return Dictionary(grouping: store.packing, by: { $0.category?.nilIfBlank ?? "Other" })
                .map { ($0.key, trips.icon(forCategory: $0.key), $0.value.sorted { $0.item < $1.item }) }
                .sorted { $0.0 < $1.0 }
                .map { (title: $0.0, icon: $0.1, items: $0.2) }
        }
    }
}

private struct PackingRow: View {
    let item: PackingItem
    let icon: String
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 10) {
                Image(systemName: item.checked ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(item.checked ? Theme.Colors.brand : .secondary)
                Text(item.item)
                    .strikethrough(item.checked)
                    .foregroundStyle(item.checked ? .secondary : .primary)
                Spacer()
                if item.category != nil {
                    Image(systemName: icon).foregroundStyle(.secondary).font(.caption)
                }
            }
        }
        .buttonStyle(.plain)
        .padding(.vertical, 4)
    }
}

private struct PackingAddView: View {
    let store: TripDetailStore
    @Environment(FamilyStore.self) private var family
    @Environment(TripsStore.self) private var trips
    @Environment(\.dismiss) private var dismiss

    @State private var memberID: UUID?
    @State private var item = ""
    @State private var categoryText = ""
    @State private var pendingIcon = "shippingbox"
    @State private var showIconPicker = false

    var body: some View {
        NavigationStack {
            Form {
                Picker("For", selection: $memberID) {
                    Text("Choose…").tag(UUID?.none)
                    ForEach(family.members) { Text($0.name).tag(UUID?.some($0.id)) }
                }
                TextField("Item", text: $item)

                Section("Category") {
                    ComboField(
                        placeholder: "Search or add a category",
                        text: $categoryText,
                        options: trips.packingCategories.map { .init(id: $0.id.uuidString, name: $0.name, icon: $0.icon) },
                        onAdd: { _ in showIconPicker = true })
                }
            }
            .navigationTitle("Add Item")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { Task { await add() } }
                        .disabled(memberID == nil || item.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear { if memberID == nil { memberID = family.currentMember?.id } }
            .sheet(isPresented: $showIconPicker) {
                IconPicker(current: pendingIcon) { icon in
                    pendingIcon = icon
                    if let fid = family.familyID {
                        Task { await trips.createPackingCategory(familyID: fid, name: categoryText, icon: icon) }
                    }
                }
            }
        }
    }

    private func add() async {
        guard let memberID else { return }
        let new = PackingItem(tripID: store.tripID, memberID: memberID, item: item,
                              category: categoryText.nilIfBlank)
        await store.savePacking(new)
        dismiss()
    }
}

/// Manage category icons — every category has an editable icon.
private struct ManageCategoriesView: View {
    @Environment(TripsStore.self) private var trips
    @Environment(\.dismiss) private var dismiss
    @State private var editing: PackingCategoryItem?

    var body: some View {
        NavigationStack {
            List(trips.packingCategories) { cat in
                Button { editing = cat } label: {
                    HStack(spacing: 12) {
                        Image(systemName: cat.icon)
                            .foregroundStyle(Theme.Colors.brand).frame(width: 28)
                        Text(cat.name).foregroundStyle(.primary)
                        Spacer()
                        Image(systemName: "pencil").foregroundStyle(.secondary).font(.caption)
                    }
                }
            }
            .navigationTitle("Categories")
            #if !targetEnvironment(macCatalyst)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .sheet(item: $editing) { cat in
                IconPicker(current: cat.icon) { icon in
                    Task { await trips.updatePackingCategoryIcon(cat, icon: icon) }
                }
            }
        }
    }
}
