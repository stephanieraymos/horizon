import SwiftUI

/// A secondary bucket inside a primary group (e.g. "Costco" under a tag).
private struct ShopSubGroup: Identifiable {
    var id: String { title ?? "" }
    let title: String?
    let icon: String?
    let items: [Expense]
}

private struct ShopPrimaryGroup: Identifiable {
    var id: String { title }
    let title: String
    let icon: String
    let subgroups: [ShopSubGroup]
    var allItems: [Expense] { subgroups.flatMap(\.items) }
}

/// Full-page shopping list — mirrors the packing list: group by Tag or Store,
/// optionally nested by the other under colored sub-headers, drag to re-group,
/// filter by store, and check items off (which moves them into Expenses).
struct ShoppingListView: View {
    let store: TripDetailStore
    let trip: Trip
    let familyID: UUID
    @Environment(FamilyStore.self) private var family
    @Environment(TripsStore.self) private var trips

    enum Grouping: String, CaseIterable { case tag = "Tag", store = "Store" }
    // Persisted so the grouping choice survives relaunches (as the old inline
    // shopping view did).
    @AppStorage("shopping.groupByStore") private var groupByStore = false
    @AppStorage("shopping.subGroupOn") private var subGroupOn = true
    private var grouping: Grouping { groupByStore ? .store : .tag }
    @State private var storeFilter: String?
    @State private var editing: Expense?
    @State private var dropTargetTitle: String?

    private static let defaultTags = ["Food / Kitchen", "Gear / Tools", "Clothing", "Toiletries", "Other"]

    /// The active secondary dimension, or nil when sub-grouping is off.
    private var activeSub: Grouping? {
        guard subGroupOn else { return nil }
        return grouping == .tag ? .store : .tag
    }

    private func title(for dim: Grouping, item: Expense) -> String {
        switch dim {
        case .tag:   return item.tag?.nilIfBlank ?? "Other"
        case .store: return item.purchasedFrom?.nilIfBlank ?? "No store"
        }
    }
    private func icon(for dim: Grouping) -> String { dim == .tag ? "tag" : "storefront" }

    private var storesInList: [String] {
        Array(Set(store.shoppingItems.compactMap { $0.purchasedFrom?.nilIfBlank })).sorted()
    }

    private var filtered: [Expense] {
        guard let f = storeFilter else { return store.shoppingItems }
        return store.shoppingItems.filter { $0.purchasedFrom?.nilIfBlank == f }
    }

    /// Alphabetical, but the catch-all buckets ("Other" / "No store") sort last.
    private func catchAllLast(_ a: String, _ b: String) -> Bool {
        let isCatch: (String) -> Bool = { $0 == "Other" || $0 == "No store" }
        if isCatch(a) != isCatch(b) { return !isCatch(a) }
        return a.localizedCaseInsensitiveCompare(b) == .orderedAscending
    }

    private var primaryGroups: [ShopPrimaryGroup] {
        Dictionary(grouping: filtered, by: { title(for: grouping, item: $0) })
            .map { pTitle, pItems -> ShopPrimaryGroup in
                let subgroups: [ShopSubGroup]
                if let sub = activeSub {
                    subgroups = Dictionary(grouping: pItems, by: { title(for: sub, item: $0) })
                        .map { sTitle, sItems in
                            ShopSubGroup(title: sTitle, icon: icon(for: sub),
                                         items: sItems.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending })
                        }
                        .sorted { catchAllLast($0.title ?? "", $1.title ?? "") }
                } else {
                    subgroups = [ShopSubGroup(title: nil, icon: nil,
                                              items: pItems.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending })]
                }
                return ShopPrimaryGroup(title: pTitle, icon: icon(for: grouping), subgroups: subgroups)
            }
            .sorted { catchAllLast($0.title, $1.title) }
    }

    private static let headerPalette: [Color] = [.blue, .indigo, .purple, .pink, .orange, .green, .teal, .brown]
    private func headerColor(_ title: String) -> Color {
        let sum = title.unicodeScalars.reduce(UInt32(0)) { $0 &+ $1.value }
        return Self.headerPalette[Int(sum) % Self.headerPalette.count]
    }

    var body: some View {
        List {
            if store.shoppingItems.isEmpty {
                ContentUnavailableView("Nothing to buy yet", systemImage: "cart",
                    description: Text("Add items, then check them off as you shop."))
            } else {
                Section {
                    Picker("Group by", selection: Binding(
                        get: { grouping }, set: { groupByStore = ($0 == .store) })) {
                        ForEach(Grouping.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    if !storesInList.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                chip("All", selected: storeFilter == nil) { storeFilter = nil }
                                ForEach(storesInList, id: \.self) { s in
                                    chip(s, selected: storeFilter == s) { storeFilter = (storeFilter == s ? nil : s) }
                                }
                            }
                        }
                    }
                    HStack {
                        Text("\(filtered.count) to buy").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                    }
                }
                ForEach(primaryGroups) { group in
                    Section {
                        ForEach(group.subgroups) { sub in
                            if sub.title != nil { subHeader(sub, color: headerColor(group.title)) }
                            ForEach(sub.items) { item in
                                PurchaseRow(item: item,
                                            onToggle: { Task { await store.togglePurchased(item, defaultPayer: family.currentMember?.id) } },
                                            onEdit: { editing = item })
                                    .draggable(item.id.uuidString)
                                    .swipeActions(edge: .trailing) {
                                        Button(role: .destructive) { Task { await store.deleteExpense(item) } } label: {
                                            Label("Delete", systemImage: "trash")
                                        }
                                    }
                            }
                        }
                    } header: {
                        header(for: group)
                    }
                }
            }
        }
        .navigationTitle("Shopping")
        #if !targetEnvironment(macCatalyst)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Picker("Then by", selection: $subGroupOn) {
                        Text("No sub-groups").tag(false)
                        Text("Sub-group by \(grouping == .tag ? "store" : "tag")").tag(true)
                    }
                    Divider()
                    Button("Add item", systemImage: "plus") { editing = newItem(tag: nil, store: storeFilter) }
                } label: { Image(systemName: "ellipsis.circle") }
            }
        }
        .sheet(item: $editing) { p in
            PurchaseEditView(store: store, familyID: familyID, item: p,
                             tagOptions: (Set(Self.defaultTags).union(store.shoppingTags)).sorted())
        }
        .onChange(of: storesInList) { _, newStores in
            if let f = storeFilter, !newStores.contains(f) { storeFilter = nil }
        }
    }

    @ViewBuilder
    private func header(for group: ShopPrimaryGroup) -> some View {
        HStack(spacing: 6) {
            Image(systemName: group.icon).font(.footnote)
            Text(group.title).font(.subheadline.weight(.semibold))
            Spacer()
            Button {
                editing = newItem(tag: grouping == .tag ? group.allItems.first?.tag : nil,
                                  store: grouping == .store ? group.allItems.first?.purchasedFrom : storeFilter)
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
        .background(dropTargetTitle == group.title ? headerColor(group.title).opacity(0.18) : Color.clear,
                    in: RoundedRectangle(cornerRadius: 6))
        .contentShape(Rectangle())
        .dropDestination(for: String.self) { ids, _ in
            Task { await moveItems(ids, toPrimary: group) }
            return true
        } isTargeted: { dropTargetTitle = $0 ? group.title : nil }
    }

    private func subHeader(_ sub: ShopSubGroup, color: Color) -> some View {
        HStack(spacing: 6) {
            if let icon = sub.icon { Image(systemName: icon).font(.caption2) }
            Text(sub.title ?? "").font(.caption.weight(.semibold)).textCase(.uppercase).kerning(0.4)
            Spacer()
            Button {
                editing = newItem(tag: sub.items.first?.tag, store: sub.items.first?.purchasedFrom)
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

    private func chip(_ label: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label).font(.caption.weight(.medium)).lineLimit(1)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(selected ? Theme.Colors.brand : Color(.tertiarySystemFill), in: Capsule())
                .foregroundStyle(selected ? .white : .primary)
        }
        .buttonStyle(.plain)
    }

    private func newItem(tag: String?, store storeName: String?) -> Expense {
        var e = Expense(tripID: store.tripID, category: ExpenseCategory.merch.rawValue, status: .notPurchased)
        e.tag = tag
        e.purchasedFrom = storeName
        return e
    }

    /// Reassign dragged items to a primary group — sets the tag (Tag grouping) or
    /// store (Store grouping) to match the drop target.
    private func moveItems(_ ids: [String], toPrimary group: ShopPrimaryGroup) async {
        for id in ids {
            guard let item = store.shoppingItems.first(where: { $0.id.uuidString == id }) else { continue }
            var updated = item
            if grouping == .tag {
                updated.tag = (group.title == "Other") ? nil : group.title
            } else {
                updated.purchasedFrom = (group.title == "No store") ? nil : group.title
            }
            await store.saveExpense(updated, splits: store.splits(for: updated))
        }
    }
}
