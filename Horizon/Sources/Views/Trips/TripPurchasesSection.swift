import SwiftUI

/// The Shopping view — items still to buy (unified `fam_trip_expenses` rows with
/// a non-purchased status). Checking one off marks it purchased, moving it into
/// Expenses and the budget. Items can be grouped by tag or by store, and filtered
/// to a single store.
struct TripPurchasesSection: View {
    let store: TripDetailStore
    let familyID: UUID
    @Environment(FamilyStore.self) private var family
    @Environment(TripsStore.self) private var trips
    @State private var editing: Expense?

    @AppStorage("shopping.groupByStore") private var groupByStore = false
    @State private var storeFilter: String?
    @State private var dropTargetKey: String?

    /// Reassign dragged items to a group — sets the store (grouped-by-store) or
    /// tag (grouped-by-tag) to match the drop target, then persists.
    private func moveItems(_ ids: [String], toGroup key: String) async {
        for id in ids {
            guard let item = store.shoppingItems.first(where: { $0.id.uuidString == id }) else { continue }
            var updated = item
            if groupByStore {
                updated.purchasedFrom = (key == "No store") ? nil : key
            } else {
                updated.tag = (key == "Other") ? nil : key
            }
            await store.saveExpense(updated, splits: store.splits(for: updated))
        }
    }

    private static let defaultTags = ["Food / Kitchen", "Gear / Tools", "Clothing", "Toiletries", "Other"]

    private func newItem() -> Expense {
        Expense(tripID: store.tripID, category: ExpenseCategory.merch.rawValue, status: .notPurchased)
    }

    /// Groups to render: by store or by tag, narrowed to `storeFilter` when set.
    private var displayGroups: [(key: String, items: [Expense])] {
        let base: [(key: String, items: [Expense])] = groupByStore
            ? store.shoppingByStore.map { (key: $0.store, items: $0.items) }
            : store.shoppingByTag.map { (key: $0.tag, items: $0.items) }
        guard let f = storeFilter else { return base }
        return base.compactMap { g in
            let items = g.items.filter { $0.purchasedFrom?.nilIfBlank == f }
            return items.isEmpty ? nil : (key: g.key, items: items)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Shopping").font(.title3.bold())
                Spacer()
                Button { editing = newItem() } label: {
                    Image(systemName: "plus.circle.fill").font(.title3)
                }
                .tint(Theme.Colors.brand)
            }

            if store.shoppingItems.isEmpty {
                Text("Build a shopping list for this trip. Check items off to move them into Expenses.")
                    .font(.callout).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding().background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 12))
            } else {
                HStack {
                    Label("\(store.shoppingToBuyCount) to buy", systemImage: "cart")
                    Spacer()
                    if let est = TripFormat.money(store.shoppingProjected), store.shoppingProjected > 0 {
                        Text("\(est) est.").foregroundStyle(.secondary)
                    }
                }
                .font(.subheadline)
                .padding().background(Theme.Colors.brand.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))

                controls

                ForEach(displayGroups, id: \.key) { group in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(group.key).font(.subheadline.bold()).foregroundStyle(.secondary)
                        ForEach(group.items) { item in
                            PurchaseRow(item: item,
                                        onToggle: { Task { await store.togglePurchased(item, defaultPayer: family.currentMember?.id) } },
                                        onEdit: { editing = item })
                                .draggable(item.id.uuidString)
                                .contextMenu {
                                    Button("Edit") { editing = item }
                                    Button("Delete", role: .destructive) { Task { await store.deleteExpense(item) } }
                                }
                        }
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(dropTargetKey == group.key ? Theme.Colors.brand.opacity(0.12) : .clear,
                                in: RoundedRectangle(cornerRadius: 10))
                    // Drop an item here to move it into this store / tag group.
                    .dropDestination(for: String.self) { ids, _ in
                        Task { await moveItems(ids, toGroup: group.key) }
                        return true
                    } isTargeted: { dropTargetKey = $0 ? group.key : nil }
                }
            }
        }
        .sheet(item: $editing) { p in
            PurchaseEditView(store: store, familyID: familyID, item: p,
                             tagOptions: (Set(Self.defaultTags).union(store.shoppingTags)).sorted())
        }
    }

    /// Group-by-store toggle + store filter chips. Only shown once at least one
    /// item has a store (otherwise there's nothing to filter or group by).
    @ViewBuilder private var controls: some View {
        let stores = store.shoppingStoresInList
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button {
                    groupByStore.toggle()
                } label: {
                    Label(groupByStore ? "Grouped by store" : "Grouped by tag",
                          systemImage: groupByStore ? "storefront" : "tag")
                        .font(.caption.weight(.medium))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.Colors.brand)
                Spacer()
            }
            if !stores.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        chip("All", selected: storeFilter == nil) { storeFilter = nil }
                        ForEach(stores, id: \.self) { s in
                            chip(s, selected: storeFilter == s) {
                                storeFilter = (storeFilter == s ? nil : s)
                            }
                        }
                    }
                    .padding(.vertical, 1)
                }
            }
        }
        // Drop a stale filter if its store no longer has any to-buy items.
        .onChange(of: stores) { _, newStores in
            if let f = storeFilter, !newStores.contains(f) { storeFilter = nil }
        }
    }

    private func chip(_ label: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.caption.weight(.medium))
                .lineLimit(1)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(selected ? Theme.Colors.brand : Color(.tertiarySystemFill),
                            in: Capsule())
                .foregroundStyle(selected ? .white : .primary)
        }
        .buttonStyle(.plain)
    }
}

private struct PurchaseRow: View {
    let item: Expense
    let onToggle: () -> Void
    let onEdit: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onToggle) {
                Image(systemName: item.status.systemImage)
                    .foregroundStyle(item.status == .purchased ? Theme.Colors.brand : .secondary)
            }
            .buttonStyle(.plain)

            Button(action: onEdit) {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(item.name).lineLimit(1)
                            .strikethrough(item.status == .purchased)
                            .foregroundStyle(item.status == .purchased ? .secondary : .primary)
                        if item.status == .inCart {
                            Text("In cart").font(.caption2).foregroundStyle(Theme.Colors.brand)
                        } else if let from = item.purchasedFrom?.nilIfBlank {
                            Text(from).font(.caption2).foregroundStyle(.secondary)
                        }
                        if let notes = item.notes?.nilIfBlank {
                            Text(notes).font(.caption2).foregroundStyle(.tertiary).lineLimit(2)
                        }
                    }
                    Spacer()
                    if let amt = TripFormat.money(item.amountDollars) {
                        Text(amt).font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if let url = item.linkURL {
                Link(destination: url) { Image(systemName: "link").font(.caption) }
                    .buttonStyle(.plain).foregroundStyle(Theme.Colors.brand)
            }
        }
        .padding(.vertical, 3)
    }
}

private struct PurchaseEditView: View {
    let store: TripDetailStore
    let familyID: UUID
    @Environment(FamilyStore.self) private var family
    @Environment(TripsStore.self) private var trips
    @Environment(\.dismiss) private var dismiss

    @State private var draft: Expense
    @State private var amountText: String
    @State private var tagText: String
    @State private var storeText: String
    let tagOptions: [String]

    init(store: TripDetailStore, familyID: UUID, item: Expense, tagOptions: [String]) {
        self.store = store
        self.familyID = familyID
        self.tagOptions = tagOptions
        _draft = State(initialValue: item)
        _amountText = State(initialValue: item.amount == 0 ? "" : String(format: "%.2f", item.amount))
        _tagText = State(initialValue: item.tag ?? "")
        _storeText = State(initialValue: item.purchasedFrom ?? "")
    }

    private var nameBinding: Binding<String> {
        Binding(get: { draft.description ?? "" }, set: { draft.description = $0.nilIfBlank })
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Item", text: nameBinding)
                    Picker("Status", selection: $draft.status) {
                        ForEach(PurchaseStatus.allCases, id: \.self) { s in
                            Label(s.label, systemImage: s.systemImage).tag(s)
                        }
                    }
                }
                Section("Tag") {
                    ComboField(placeholder: "Search or add a tag", text: $tagText,
                               options: tagOptions.map { .init(id: $0, name: $0, icon: "tag") },
                               pickIcon: "tag")
                }
                Section("Store") {
                    ComboField(placeholder: "Search or add a store / site", text: $storeText,
                               options: trips.shoppingStores.map { .init(id: $0.id.uuidString, name: $0.name, icon: "storefront") },
                               pickIcon: "storefront",
                               onAdd: { name in
                                   Task { await trips.createShoppingStore(familyID: familyID, name: name) }
                               })
                }
                Section("Details") {
                    TextField("Amount (USD)", text: $amountText)
                        #if !targetEnvironment(macCatalyst)
                        .keyboardType(.decimalPad)
                        #endif
                    TextField("Link (product URL)", text: Binding(
                        get: { draft.link ?? "" }, set: { draft.link = $0.nilIfBlank }))
                        .textContentType(.URL)
                        .autocorrectionDisabled()
                        #if !targetEnvironment(macCatalyst)
                        .textInputAutocapitalization(.never)
                        #endif
                }
                Section("Notes") {
                    TextField("Paste model, item #, specs…", text: Binding(
                        get: { draft.notes ?? "" }, set: { draft.notes = $0.nilIfBlank }),
                        axis: .vertical)
                        .lineLimit(2...8)
                }
            }
            .navigationTitle((draft.description ?? "").isEmpty ? "New Item" : "Edit Item")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await save() } }
                        .disabled((draft.description ?? "").trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private func save() async {
        draft.tag = tagText.nilIfBlank
        draft.purchasedFrom = storeText.nilIfBlank
        // Persist a brand-new store name to the managed list so it's reusable.
        if let name = storeText.nilIfBlank, trips.store(named: name) == nil {
            await trips.createShoppingStore(familyID: familyID, name: name)
        }
        draft.amount = Double(amountText.replacingOccurrences(of: ",", with: "")) ?? 0
        // Marking purchased here defaults the payer to the current member.
        if draft.isPurchased, draft.paidBy == nil {
            draft.paidBy = family.currentMember?.id
            if draft.spentOn == nil { draft.spentOn = Date() }
        }
        await store.saveExpense(draft, splits: store.splits(for: draft))
        dismiss()
    }
}
