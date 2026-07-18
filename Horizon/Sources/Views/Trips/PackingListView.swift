import SwiftUI

/// Seed for a quick-add — pre-fills the new item's person and/or category (from
/// a group header or the active filters).
private struct PackingAddContext: Identifiable {
    let id = UUID()
    var person: UUID?
    var category: String?
}

/// A secondary bucket inside a primary group (e.g. "Bathroom" under a person).
/// `title == nil` means sub-grouping is off — just a flat list of items.
private struct PackSubGroup: Identifiable {
    // Stable identity so ForEach diffs by title, not a per-render UUID.
    var id: String { title ?? "" }
    let title: String?
    let icon: String?
    let items: [PackingItem]
}

private struct PackPrimaryGroup: Identifiable {
    var id: String { title }
    let title: String
    let icon: String
    let subgroups: [PackSubGroup]
    var allItems: [PackingItem] { subgroups.flatMap(\.items) }
}

/// Full-page packing list: filter by person and category, grouped, with per-item
/// editing (each item is assigned to a traveler on the trip).
struct PackingListView: View {
    let store: TripDetailStore
    let trip: Trip
    @Environment(FamilyStore.self) private var family
    @Environment(TripsStore.self) private var trips

    @State private var grouping: Grouping = .person
    @State private var subGroupOn = true
    @State private var personFilter: UUID?
    @State private var categoryFilter: String?
    @State private var editingItem: PackingItem?
    @State private var addContext: PackingAddContext?
    @State private var showApplyTemplate = false
    @State private var showSaveTemplate = false
    @State private var showManageCategories = false
    @State private var dropTargetTitle: String?

    enum Grouping: String, CaseIterable { case person = "Person", category = "Category" }

    /// Reassign dragged items to a primary group — sets the person (Person
    /// grouping) or category (Category grouping) to match the drop target.
    private func moveItems(_ ids: [String], toPrimary group: PackPrimaryGroup) async {
        let targetPerson = group.allItems.first?.memberID
        for id in ids {
            guard let item = store.packing.first(where: { $0.id.uuidString == id }) else { continue }
            var updated = item
            if grouping == .person {
                guard updated.memberID != targetPerson else { continue }
                updated.memberID = targetPerson
            } else {
                let target = group.title == "Other" ? nil : group.title
                guard (updated.category?.nilIfBlank ?? "Other") != group.title else { continue }
                updated.category = target
            }
            await store.savePacking(updated)
        }
    }

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
                ForEach(primaryGroups) { group in
                    Section {
                        ForEach(group.subgroups) { sub in
                            if sub.title != nil { subHeader(sub, color: headerColor(group.title)) }
                            ForEach(sub.items) { item in
                                PackingRow(item: item, icon: trips.icon(forCategory: item.category),
                                           subtitle: activeSub == nil ? subtitle(for: item) : nil) {
                                    Task { await store.togglePacking(item) }
                                }
                                .contentShape(Rectangle())
                                .onTapGesture { editingItem = item }
                                .draggable(item.id.uuidString)
                                .swipeActions(edge: .trailing) {
                                    Button(role: .destructive) { Task { await store.deletePacking(item) } } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
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
                                    person: grouping == .person ? group.allItems.first?.memberID : personFilter,
                                    category: grouping == .category ? group.allItems.first?.category : categoryFilter)
                            } label: {
                                Image(systemName: "plus.circle").font(.subheadline)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Add to \(group.title)")
                        }
                        .foregroundStyle(headerColor(group.title))
                        .textCase(nil)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 4)
                        .background(dropTargetTitle == group.title
                                    ? headerColor(group.title).opacity(0.18) : Color.clear,
                                    in: RoundedRectangle(cornerRadius: 6))
                        .contentShape(Rectangle())
                        // Drop an item's card here to reassign it to this person /
                        // category (its member/category updates automatically).
                        .dropDestination(for: String.self) { ids, _ in
                            Task { await moveItems(ids, toPrimary: group) }
                            return true
                        } isTargeted: { dropTargetTitle = $0 ? group.title : nil }
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
                    Picker("Then by", selection: $subGroupOn) {
                        Text("No sub-groups").tag(false)
                        Text("Sub-group by \(grouping == .person ? "category" : "person")").tag(true)
                    }
                    Divider()
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

    /// The active secondary dimension, or nil when sub-grouping is off (only two
    /// dimensions exist, so it's always "the other one").
    private var activeSub: Grouping? {
        guard subGroupOn else { return nil }
        return grouping == .person ? .category : .person
    }

    private func title(for dim: Grouping, item: PackingItem) -> String {
        switch dim {
        case .person: return item.memberID.flatMap { family.memberName(id: $0) } ?? "Everyone"
        case .category: return item.category?.nilIfBlank ?? "Other"
        }
    }

    private func icon(for dim: Grouping, title: String, items: [PackingItem]) -> String {
        switch dim {
        case .person: return items.first?.memberID == nil ? "person.2.circle" : "person.circle"
        case .category: return trips.icon(forCategory: title)
        }
    }

    /// Alphabetical, but the catch-all buckets ("Other" / "Everyone") sort last.
    private func subGroupBefore(_ a: String, _ b: String) -> Bool {
        let catchAll: (String) -> Bool = { $0 == "Other" || $0 == "Everyone" }
        if catchAll(a) != catchAll(b) { return !catchAll(a) }
        return a.localizedCaseInsensitiveCompare(b) == .orderedAscending
    }

    private var primaryGroups: [PackPrimaryGroup] {
        Dictionary(grouping: filtered, by: { title(for: grouping, item: $0) })
            .map { pTitle, pItems -> PackPrimaryGroup in
                let subgroups: [PackSubGroup]
                if let sub = activeSub {
                    subgroups = Dictionary(grouping: pItems, by: { title(for: sub, item: $0) })
                        .map { sTitle, sItems in
                            PackSubGroup(title: sTitle,
                                         icon: icon(for: sub, title: sTitle, items: sItems),
                                         items: sItems.sorted { $0.item < $1.item })
                        }
                        .sorted { subGroupBefore($0.title ?? "", $1.title ?? "") }
                } else {
                    subgroups = [PackSubGroup(title: nil, icon: nil, items: pItems.sorted { $0.item < $1.item })]
                }
                return PackPrimaryGroup(title: pTitle,
                                        icon: icon(for: grouping, title: pTitle, items: pItems),
                                        subgroups: subgroups)
            }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    /// Small sub-heading row shown above each secondary bucket, tinted with its
    /// parent group's colour so it reads as a sub-section, not another item.
    private func subHeader(_ sub: PackSubGroup, color: Color) -> some View {
        HStack(spacing: 6) {
            if let icon = sub.icon { Image(systemName: icon).font(.caption2) }
            Text(sub.title ?? "").font(.caption.weight(.semibold))
                .textCase(.uppercase).kerning(0.4)
            Spacer()
            Button {
                addContext = PackingAddContext(person: sub.items.first?.memberID,
                                               category: sub.items.first?.category?.nilIfBlank)
            } label: {
                Image(systemName: "plus.circle").font(.caption)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Add to \(sub.title ?? "")")
        }
        .foregroundStyle(color)
        .padding(.leading, 6)
        .listRowSeparator(.hidden)
    }

    /// Secondary label per row — the dimension not used for grouping (shown only
    /// when sub-grouping is off, since otherwise the sub-header covers it).
    private func subtitle(for item: PackingItem) -> String? {
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
