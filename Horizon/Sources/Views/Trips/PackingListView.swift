import SwiftUI

/// Seed for a quick-add — pre-fills the new item's person and/or category (from
/// a group header or the active filters).
private struct PackingAddContext: Identifiable {
    let id = UUID()
    var person: UUID?
    var category: String?
}

/// Full-page packing list: filter by person and category, grouped, with per-item
/// editing (each item is assigned to a traveler on the trip).
struct PackingListView: View {
    let store: TripDetailStore
    let trip: Trip
    @Environment(FamilyStore.self) private var family
    @Environment(TripsStore.self) private var trips

    @State private var grouping: Grouping = .person
    @State private var personFilter: UUID?
    @State private var categoryFilter: String?
    @State private var editingItem: PackingItem?
    @State private var addContext: PackingAddContext?
    @State private var showApplyTemplate = false
    @State private var showSaveTemplate = false
    @State private var showManageCategories = false

    enum Grouping: String, CaseIterable { case person = "Person", category = "Category" }

    /// Members on this trip (fallback: whole family).
    private var travelerMembers: [FamilyMember] {
        let names = Set((trip.travelers ?? []).map { $0.lowercased() })
        let onTrip = family.members.filter { names.contains($0.name.lowercased()) }
        return onTrip.isEmpty ? family.members : onTrip
    }

    /// People who actually have items (for the filter chips).
    private var peopleWithItems: [FamilyMember] {
        let ids = Set(store.packing.compactMap(\.memberID))
        return travelerMembers.filter { ids.contains($0.id) }
    }
    /// Whether any item is shared (no person).
    private var hasSharedItems: Bool { store.packing.contains { $0.memberID == nil } }
    private var categoriesPresent: [String] {
        var seen = Set<String>(); var out: [String] = []
        for p in store.packing {
            let c = p.category?.nilIfBlank ?? "Other"
            if !seen.contains(c.lowercased()) { seen.insert(c.lowercased()); out.append(c) }
        }
        return out.sorted()
    }

    private var filtered: [PackingItem] {
        store.packing.filter { item in
            (personFilter == nil || item.memberID == personFilter) &&
            (categoryFilter == nil || (item.category?.nilIfBlank ?? "Other").caseInsensitiveCompare(categoryFilter!) == .orderedSame)
        }
    }

    private var progress: (packed: Int, total: Int) {
        (filtered.filter(\.checked).count, filtered.count)
    }

    var body: some View {
        List {
            if store.packing.isEmpty {
                ContentUnavailableView("Nothing packed yet", systemImage: "bag",
                    description: Text("Add items per person, or apply a template."))
            } else {
                Section {
                    Picker("Group by", selection: $grouping) {
                        ForEach(Grouping.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    filterChips
                    HStack {
                        Text("\(progress.packed) of \(progress.total) packed")
                            .font(.caption).foregroundStyle(.secondary)
                        Spacer()
                    }
                }
                ForEach(groups, id: \.title) { group in
                    Section {
                        ForEach(group.items) { item in
                            PackingRow(item: item, icon: trips.icon(forCategory: item.category),
                                       subtitle: subtitle(for: item, in: group)) {
                                Task { await store.togglePacking(item) }
                            }
                            .contentShape(Rectangle())
                            .onTapGesture { editingItem = item }
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) { Task { await store.deletePacking(item) } } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    } header: {
                        HStack(spacing: 6) {
                            Image(systemName: group.icon).font(.footnote)
                            Text(group.title).font(.subheadline.weight(.semibold))
                            Spacer()
                            Button {
                                addContext = PackingAddContext(
                                    person: grouping == .person ? group.items.first?.memberID : personFilter,
                                    category: grouping == .category ? group.items.first?.category : categoryFilter)
                            } label: {
                                Image(systemName: "plus.circle").font(.subheadline)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Add to \(group.title)")
                        }
                        .foregroundStyle(headerColor(group.title))
                        .textCase(nil)
                    }
                }
            }
        }
        .navigationTitle("Packing")
        #if !targetEnvironment(macCatalyst)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("Add item", systemImage: "plus") {
                        addContext = PackingAddContext(person: personFilter, category: categoryFilter)
                    }
                    Button("Apply template", systemImage: "suitcase") { showApplyTemplate = true }
                    if !store.packing.isEmpty {
                        Button("Save list as template", systemImage: "square.and.arrow.down") { showSaveTemplate = true }
                    }
                    Button("Manage categories", systemImage: "tag") { showManageCategories = true }
                } label: { Image(systemName: "ellipsis.circle") }
            }
        }
        .sheet(item: $addContext) { ctx in
            PackingItemEditView(store: store, existing: nil, travelers: travelerMembers,
                                defaultPerson: ctx.person, defaultCategory: ctx.category)
        }
        .sheet(item: $editingItem) { item in
            PackingItemEditView(store: store, existing: item, travelers: travelerMembers,
                                defaultPerson: nil, defaultCategory: nil)
        }
        .sheet(isPresented: $showApplyTemplate) {
            ApplyTemplateSheet(store: store, travelerNames: trip.travelers ?? [])
        }
        .sheet(isPresented: $showSaveTemplate) {
            SaveAsTemplateSheet(packing: store.packing)
        }
        .sheet(isPresented: $showManageCategories) { ManageCategoriesView(store: store) }
    }

    // MARK: Filter chips

    private var filterChips: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !peopleWithItems.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        PackFilterChip(label: "All", active: personFilter == nil) { personFilter = nil }
                        ForEach(peopleWithItems) { m in
                            PackFilterChip(label: m.name.split(separator: " ").first.map(String.init) ?? m.name,
                                           active: personFilter == m.id) {
                                personFilter = (personFilter == m.id) ? nil : m.id
                            }
                        }
                    }
                }
            }
            if !categoriesPresent.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        PackFilterChip(label: "All", active: categoryFilter == nil) { categoryFilter = nil }
                        ForEach(categoriesPresent, id: \.self) { c in
                            PackFilterChip(label: c, active: categoryFilter?.caseInsensitiveCompare(c) == .orderedSame) {
                                categoryFilter = (categoryFilter?.caseInsensitiveCompare(c) == .orderedSame) ? nil : c
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: Grouping

    /// A tasteful, light/dark-adaptive palette for group headers so each person /
    /// category is easy to tell apart at a glance.
    private static let headerPalette: [Color] =
        [.blue, .indigo, .purple, .pink, .orange, .green, .teal, .brown]

    /// Stable colour for a group title (same person/category always gets the same
    /// colour, across launches — unlike String.hashValue which is seeded per run).
    private func headerColor(_ title: String) -> Color {
        let sum = title.unicodeScalars.reduce(UInt32(0)) { $0 &+ $1.value }
        return Self.headerPalette[Int(sum) % Self.headerPalette.count]
    }

    private var groups: [(title: String, icon: String, items: [PackingItem])] {
        switch grouping {
        case .person:
            return Dictionary(grouping: filtered, by: \.memberID)
                .map { key, items -> (String, String, [PackingItem]) in
                    let title = key.flatMap { family.memberName(id: $0) } ?? "Everyone"
                    return (title, key == nil ? "person.2.circle" : "person.circle", items.sorted { $0.item < $1.item })
                }
                .sorted { $0.0 < $1.0 }
                .map { (title: $0.0, icon: $0.1, items: $0.2) }
        case .category:
            return Dictionary(grouping: filtered, by: { $0.category?.nilIfBlank ?? "Other" })
                .map { ($0.key, trips.icon(forCategory: $0.key), $0.value.sorted { $0.item < $1.item }) }
                .sorted { $0.0 < $1.0 }
                .map { (title: $0.0, icon: $0.1, items: $0.2) }
        }
    }

    /// Secondary label per row — the dimension not used for grouping.
    private func subtitle(for item: PackingItem, in group: (title: String, icon: String, items: [PackingItem])) -> String? {
        switch grouping {
        case .person: return item.category?.nilIfBlank
        case .category: return item.memberID.flatMap { family.memberName(id: $0) } ?? "Everyone"
        }
    }
}

private struct PackFilterChip: View {
    let label: String
    let active: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.caption.weight(.medium))
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(active ? Theme.Colors.brand.opacity(0.18) : Color(.tertiarySystemFill), in: Capsule())
                .foregroundStyle(active ? Theme.Colors.brand : .secondary)
        }
        .buttonStyle(.plain)
    }
}

struct PackingRow: View {
    let item: PackingItem
    let icon: String
    var subtitle: String? = nil
    let onToggle: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onToggle) {
                Image(systemName: item.checked ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(item.checked ? Theme.Colors.brand : .secondary)
            }
            .buttonStyle(.plain)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.item)
                    .strikethrough(item.checked)
                    .foregroundStyle(item.checked ? .secondary : .primary)
                if let subtitle = subtitle?.nilIfBlank {
                    Text(subtitle).font(.caption).foregroundStyle(.tertiary)
                }
            }
            Spacer()
            Image(systemName: icon).foregroundStyle(.secondary).font(.caption)
        }
        .padding(.vertical, 2)
    }
}

/// Add or edit a packing item; the person is chosen from the trip's travelers.
struct PackingItemEditView: View {
    let store: TripDetailStore
    let existing: PackingItem?
    let travelers: [FamilyMember]
    var defaultPerson: UUID?
    var defaultCategory: String?

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
                    Text("Everyone").tag(UUID?.none)
                    ForEach(travelers) { Text($0.name).tag(UUID?.some($0.id)) }
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
            .navigationTitle(existing == nil ? "Add Item" : "Edit Item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await save() } }
                        .disabled(item.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear {
                if let e = existing {
                    memberID = e.memberID; item = e.item; categoryText = e.category ?? ""
                } else {
                    // Default to the active person filter, else "Everyone".
                    memberID = defaultPerson
                    categoryText = defaultCategory ?? ""
                }
            }
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

    private func save() async {
        // memberID may be nil — that means "Everyone" (shared), which is valid.
        let updated = PackingItem(id: existing?.id ?? UUID(), tripID: store.tripID, memberID: memberID,
                                  item: item.trimmingCharacters(in: .whitespaces),
                                  checked: existing?.checked ?? false,
                                  category: categoryText.nilIfBlank)
        await store.savePacking(updated)
        dismiss()
    }
}

/// Manage packing categories — add, rename, change icon, or delete.
struct ManageCategoriesView: View {
    let store: TripDetailStore
    @Environment(TripsStore.self) private var trips
    @Environment(\.dismiss) private var dismiss
    @State private var editing: PackingCategoryItem?
    @State private var addingNew = false

    var body: some View {
        NavigationStack {
            List {
                ForEach(trips.packingCategories) { cat in
                    Button { editing = cat } label: {
                        HStack(spacing: 12) {
                            Image(systemName: cat.icon)
                                .foregroundStyle(Theme.Colors.brand).frame(width: 28)
                            Text(cat.name).foregroundStyle(.primary)
                            Spacer()
                            Image(systemName: "pencil").foregroundStyle(.secondary).font(.caption)
                        }
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            Task { await trips.deletePackingCategory(cat) }
                        } label: { Label("Delete", systemImage: "trash") }
                    }
                }
            }
            .navigationTitle("Categories")
            #if !targetEnvironment(macCatalyst)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    Button { addingNew = true } label: { Image(systemName: "plus") }
                }
            }
            .sheet(item: $editing) { cat in CategoryEditView(store: store, category: cat) }
            .sheet(isPresented: $addingNew) { CategoryEditView(store: store, category: nil) }
        }
    }
}

/// Add or edit a single packing category (name + icon).
private struct CategoryEditView: View {
    let store: TripDetailStore
    let category: PackingCategoryItem?
    @Environment(TripsStore.self) private var trips
    @Environment(FamilyStore.self) private var family
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var icon: String
    @State private var showIconPicker = false

    init(store: TripDetailStore, category: PackingCategoryItem?) {
        self.store = store
        self.category = category
        _name = State(initialValue: category?.name ?? "")
        _icon = State(initialValue: category?.icon ?? "shippingbox")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Category name", text: $name)
                    Button { showIconPicker = true } label: {
                        HStack {
                            Text("Icon").foregroundStyle(.primary)
                            Spacer()
                            Image(systemName: icon).foregroundStyle(Theme.Colors.brand)
                        }
                    }
                }
            }
            .navigationTitle(category == nil ? "New Category" : "Edit Category")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await save() } }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .sheet(isPresented: $showIconPicker) {
                IconPicker(current: icon) { icon = $0 }
            }
        }
    }

    private func save() async {
        guard let fid = family.familyID else { return }
        if let category {
            await trips.updatePackingCategory(category, name: name, icon: icon)
            // Reload so the current trip's items reflect a renamed category.
            await store.load()
        } else {
            await trips.createPackingCategory(familyID: fid, name: name, icon: icon)
        }
        dismiss()
    }
}
