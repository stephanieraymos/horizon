import SwiftUI

/// A secondary bucket inside a primary group (e.g. "Costco" under a category).
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

/// Unified money page: a Shopping | Expenses segmented toggle up top, the group-by
/// choice (Category / Store) tucked into the ⋯ menu. Both modes share the same
/// grouping, sub-groups, store filter, and drag-to-regroup; Expenses mode also
/// shows the spend + settle-up summary. Checking a shopping item off moves it into
/// Expenses carrying its category (they share the one `category` field now).
struct TripMoneyView: View {
    let store: TripDetailStore
    let trip: Trip
    let familyID: UUID
    @Environment(FamilyStore.self) private var family
    @Environment(TripsStore.self) private var trips

    enum Mode: String, CaseIterable { case shopping = "Shopping", expenses = "Expenses" }
    enum Grouping: String, CaseIterable { case category = "Category", store = "Where" }
    /// Catch-all bucket label for items with no "where" set.
    private static let noWhere = "No location"

    // Persisted so Shopping/Expenses + the grouping choice survive relaunches.
    @AppStorage("money.mode") private var mode: Mode = .shopping
    @AppStorage("shopping.groupByStore") private var groupByStore = false
    @AppStorage("shopping.subGroupOn") private var subGroupOn = true
    private var grouping: Grouping { groupByStore ? .store : .category }
    @State private var storeFilter: String?
    @State private var sheet: ActiveSheet?
    @State private var dropTargetTitle: String?
    @State private var showConverter = false
    @State private var query = ""
    // Actual-price prompt: set when checking off a to-buy item that has no price.
    @State private var pricingItem: Expense?
    @State private var priceText = ""
    // Undo toast (move-to-shopping).
    @State private var toast: MoneyToast?
    @State private var toastToken = 0

    private enum ActiveSheet: Identifiable {
        case shop(Expense), expense(Expense)
        var id: UUID { switch self { case .shop(let e), .expense(let e): return e.id } }
    }

    struct MoneyToast { let message: String; let undo: () -> Void }

    /// The items the current mode shows: to-buy list vs. purchased ledger.
    private var sourceItems: [Expense] {
        mode == .shopping ? store.shoppingItems : store.purchasedExpenses
    }

    /// Shared category vocabulary drawn from every spending item — the "same
    /// categories database" across shopping and expenses.
    private var categoryOptions: [String] {
        Set(ExpenseCategory.allCases.map(\.rawValue))
            .union(store.expenses.map(\.category))
            .sorted()
    }

    /// The active secondary dimension, or nil when sub-grouping is off.
    private var activeSub: Grouping? {
        guard subGroupOn else { return nil }
        return grouping == .category ? .store : .category
    }

    private func title(for dim: Grouping, item: Expense) -> String {
        switch dim {
        case .category: return item.category.nilIfBlank ?? "Other"
        case .store:    return item.purchasedFrom?.nilIfBlank ?? Self.noWhere
        }
    }
    private func icon(for dim: Grouping) -> String { dim == .category ? "tag" : "mappin.and.ellipse" }

    private var storesInList: [String] {
        Array(Set(sourceItems.compactMap { $0.purchasedFrom?.nilIfBlank })).sorted()
    }

    private var filtered: [Expense] {
        var items = sourceItems
        if let f = storeFilter { items = items.filter { $0.purchasedFrom?.nilIfBlank == f } }
        let q = query.trimmingCharacters(in: .whitespaces)
        if !q.isEmpty {
            items = items.filter {
                $0.name.localizedCaseInsensitiveContains(q)
                    || ($0.notes?.localizedCaseInsensitiveContains(q) ?? false)
                    || ($0.purchasedFrom?.localizedCaseInsensitiveContains(q) ?? false)
                    || $0.category.localizedCaseInsensitiveContains(q)
            }
        }
        return items
    }

    /// Alphabetical, but the catch-all buckets ("Other" / "No store") sort last.
    private func catchAllLast(_ a: String, _ b: String) -> Bool {
        let isCatch: (String) -> Bool = { $0 == "Other" || $0 == Self.noWhere }
        if isCatch(a) != isCatch(b) { return !isCatch(a) }
        return a.localizedCaseInsensitiveCompare(b) == .orderedAscending
    }

    /// Expenses read best newest-first (a ledger); the shopping list reads best
    /// alphabetically (scan while you shop).
    private func sortedItems(_ items: [Expense]) -> [Expense] {
        if mode == .expenses {
            return items.sorted { ($0.spentOn ?? $0.loggedAt ?? .distantPast) > ($1.spentOn ?? $1.loggedAt ?? .distantPast) }
        }
        return items.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var primaryGroups: [ShopPrimaryGroup] {
        Dictionary(grouping: filtered, by: { title(for: grouping, item: $0) })
            .map { pTitle, pItems -> ShopPrimaryGroup in
                let subgroups: [ShopSubGroup]
                if let sub = activeSub {
                    subgroups = Dictionary(grouping: pItems, by: { title(for: sub, item: $0) })
                        .map { sTitle, sItems in
                            ShopSubGroup(title: sTitle, icon: icon(for: sub), items: sortedItems(sItems))
                        }
                        .sorted { catchAllLast($0.title ?? "", $1.title ?? "") }
                } else {
                    subgroups = [ShopSubGroup(title: nil, icon: nil, items: sortedItems(pItems))]
                }
                return ShopPrimaryGroup(title: pTitle, icon: icon(for: grouping), subgroups: subgroups)
            }
            .sorted { catchAllLast($0.title, $1.title) }
    }

    /// Sum of a group's item amounts — shown in headers in Expenses mode.
    private func groupTotal(_ items: [Expense]) -> Double { items.reduce(0) { $0 + $1.amount } }

    private static let headerPalette: [Color] = [.blue, .indigo, .purple, .pink, .orange, .green, .teal, .brown]
    private func headerColor(_ title: String) -> Color {
        let sum = title.unicodeScalars.reduce(UInt32(0)) { $0 &+ $1.value }
        return Self.headerPalette[Int(sum) % Self.headerPalette.count]
    }

    private var emptyView: some View {
        mode == .shopping
            ? ContentUnavailableView("Nothing to buy yet", systemImage: "cart",
                description: Text("Add items, then check them off as you shop."))
            : ContentUnavailableView("No expenses yet", systemImage: "creditcard",
                description: Text("Log spending, or check items off the shopping list."))
    }

    var body: some View {
        List {
            if mode == .expenses && !store.purchasedExpenses.isEmpty {
                Section { ExpenseSummaryView(store: store, trip: trip) }
                    .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                    .listRowBackground(Color.clear)
            }

            if sourceItems.isEmpty {
                Section { emptyView }.listRowBackground(Color.clear)
            } else {
                Section {
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
                        Text(countLabel).font(.caption).foregroundStyle(.secondary)
                        Spacer()
                    }
                }
                if primaryGroups.isEmpty {
                    Section {
                        if !query.trimmingCharacters(in: .whitespaces).isEmpty {
                            ContentUnavailableView.search(text: query)
                        } else {
                            ContentUnavailableView("Nothing here", systemImage: "tray",
                                description: Text("No items match this filter."))
                        }
                    }
                    .listRowBackground(Color.clear)
                }
                ForEach(primaryGroups) { group in
                    Section {
                        ForEach(group.subgroups) { sub in
                            if sub.title != nil { subHeader(sub, in: group, color: headerColor(group.title)) }
                            ForEach(sub.items) { item in
                                PurchaseRow(item: item,
                                            onToggle: mode == .shopping ? { checkOff(item) } : nil,
                                            strikeWhenPurchased: mode == .shopping)
                                    .contentShape(Rectangle())
                                    .onTapGesture { open(item) }
                                    .draggable(item.id.uuidString)
                                    .dropDestination(for: String.self) { ids, _ in
                                        Task { await moveItems(ids, ontoItemLike: item) }
                                        return true
                                    }
                                    .contextMenu {
                                        Button("Edit", systemImage: "pencil") { open(item) }
                                        Menu("Move to category") {
                                            ForEach(categoryOptions, id: \.self) { c in
                                                Button { Task { await setItemCategory(item, c) } } label: {
                                                    Label(c, systemImage: item.category == c ? "checkmark" : ExpenseCategory.icon(for: c))
                                                }
                                            }
                                        }
                                        Menu("Move to where") {
                                            Button { Task { await setItemWhere(item, nil) } } label: {
                                                Label(Self.noWhere, systemImage: item.purchasedFrom?.nilIfBlank == nil ? "checkmark" : "mappin.slash")
                                            }
                                            ForEach(trips.shoppingStores) { s in
                                                Button { Task { await setItemWhere(item, s.name) } } label: {
                                                    Label(s.name, systemImage: item.purchasedFrom == s.name ? "checkmark" : "mappin.and.ellipse")
                                                }
                                            }
                                        }
                                        if mode == .expenses {
                                            Button("Move to shopping", systemImage: "cart") { moveToShopping(item) }
                                        }
                                        Button("Delete", systemImage: "trash", role: .destructive) {
                                            Task { await store.deleteExpense(item) }
                                        }
                                    }
                                    .swipeActions(edge: .leading) {
                                        if mode == .shopping {
                                            Button { checkOff(item) } label: { Label("Bought", systemImage: "checkmark") }
                                                .tint(Theme.Colors.brand)
                                        } else {
                                            Button { moveToShopping(item) } label: { Label("To shopping", systemImage: "cart") }
                                                .tint(Theme.Colors.brand)
                                        }
                                    }
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
        .listSectionSpacing(.compact)
        .safeAreaInset(edge: .top, spacing: 0) {
            Picker("Mode", selection: $mode) {
                ForEach(Mode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal).padding(.top, 6).padding(.bottom, 10)
            .background(.bar)
        }
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always),
                    prompt: mode == .shopping ? "Search items" : "Search expenses")
        .overlay(alignment: .bottom) { undoToast }
        .task(id: toastToken) {
            guard toast != nil else { return }
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            withAnimation { toast = nil }
        }
        .alert("Actual price", isPresented: Binding(
            get: { pricingItem != nil }, set: { if !$0 { pricingItem = nil } })) {
            TextField("Amount (USD)", text: $priceText)
                #if !targetEnvironment(macCatalyst)
                .keyboardType(.decimalPad)
                #endif
            Button("Save") { confirmPrice(save: true) }
            Button("Log without price") { confirmPrice(save: false) }
            Button("Cancel", role: .cancel) { pricingItem = nil }
        } message: {
            Text("How much did you pay for \(pricingItem?.name ?? "this")?")
        }
        .navigationTitle("Money")
        #if !targetEnvironment(macCatalyst)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Picker("Group by", selection: Binding(
                        get: { grouping }, set: { groupByStore = ($0 == .store) })) {
                        ForEach(Grouping.allCases, id: \.self) { Label($0.rawValue, systemImage: icon(for: $0)).tag($0) }
                    }
                    Picker("Then by", selection: $subGroupOn) {
                        Text("No sub-groups").tag(false)
                        Text("Sub-group by \(grouping == .category ? "store" : "category")").tag(true)
                    }
                    Divider()
                    Button("Add", systemImage: "plus") { addItem(category: nil, store: storeFilter) }
                    Button("Currency converter", systemImage: "dollarsign.arrow.circlepath") { showConverter = true }
                } label: { Image(systemName: "ellipsis.circle") }
            }
        }
        .sheet(isPresented: $showConverter) { CurrencyConverterView() }
        .sheet(item: $sheet) { active in
            switch active {
            case .shop(let item):
                PurchaseEditView(store: store, familyID: familyID, item: item,
                                 categoryOptions: categoryOptions)
            case .expense(let item):
                ExpenseEditView(store: store, expense: item, travelerNames: trip.travelers ?? [])
            }
        }
        .onChange(of: storesInList) { _, newStores in
            if let f = storeFilter, !newStores.contains(f) { storeFilter = nil }
        }
        .onChange(of: mode) { _, _ in storeFilter = nil }
    }

    private var countLabel: String {
        mode == .shopping ? "\(filtered.count) to buy" : "\(filtered.count) logged"
    }

    /// Opens the right editor for the tapped item based on the current mode.
    private func open(_ item: Expense) {
        sheet = mode == .shopping ? .shop(item) : .expense(item)
    }

    // MARK: Row actions

    /// Check a to-buy item off into Expenses. If it has no price yet, ask for the
    /// actual amount first so the ledger total stays honest.
    private func checkOff(_ item: Expense) {
        guard !item.isPurchased else { return }
        if item.amount == 0 {
            priceText = ""
            pricingItem = item
        } else {
            Task { await store.togglePurchased(item, defaultPayer: family.currentMember?.id) }
        }
    }

    /// Resolves the actual-price prompt: log with the entered amount, or skip and
    /// log at $0.
    private func confirmPrice(save: Bool) {
        guard let item = pricingItem else { return }
        pricingItem = nil
        var updated = item
        updated.status = .purchased
        if updated.paidBy == nil { updated.paidBy = family.currentMember?.id }
        if updated.spentOn == nil { updated.spentOn = Date() }
        if save { updated.amount = Double(priceText.replacingOccurrences(of: ",", with: "")) ?? 0 }
        Task { await store.saveExpense(updated, splits: store.splits(for: updated)) }
    }

    /// Move a logged expense back to the shopping list, with an Undo toast.
    private func moveToShopping(_ item: Expense) {
        let restored = item   // was purchased — keep a copy to restore
        Task { await store.togglePurchased(item, defaultPayer: family.currentMember?.id) }
        showToast("Moved to shopping") {
            Task { await store.saveExpense(restored, splits: store.splits(for: restored)) }
        }
    }

    private func markAllPurchased(_ group: ShopPrimaryGroup) {
        let items = group.allItems.filter { !$0.isPurchased }
        guard !items.isEmpty else { return }
        Task { for item in items { await store.togglePurchased(item, defaultPayer: family.currentMember?.id) } }
    }

    private func moveAllToShopping(_ group: ShopPrimaryGroup) {
        let items = group.allItems.filter(\.isPurchased)
        guard !items.isEmpty else { return }
        Task { for item in items { await store.togglePurchased(item, defaultPayer: family.currentMember?.id) } }
    }

    private func showToast(_ message: String, undo: @escaping () -> Void) {
        withAnimation { toast = MoneyToast(message: message, undo: undo) }
        toastToken += 1
    }

    @ViewBuilder private var undoToast: some View {
        if let t = toast {
            HStack(spacing: 12) {
                Text(t.message).font(.subheadline).foregroundStyle(.white)
                Spacer()
                Button("Undo") { t.undo(); withAnimation { toast = nil } }
                    .font(.subheadline.weight(.semibold)).foregroundStyle(Theme.Colors.brand)
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
            .background(Color.black.opacity(0.85), in: Capsule())
            .padding(.horizontal, 24).padding(.bottom, 12)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    /// Builds a new item pre-filled with the group's category/store, then routes to
    /// the mode's editor (shopping → to-buy item, expenses → a logged expense).
    private func addItem(category: String?, store storeName: String?) {
        if mode == .shopping {
            var e = Expense(tripID: store.tripID,
                            category: category?.nilIfBlank ?? ExpenseCategory.other.rawValue,
                            status: .notPurchased)
            e.purchasedFrom = storeName
            sheet = .shop(e)
        } else {
            let e = Expense(tripID: store.tripID,
                            category: category?.nilIfBlank ?? ExpenseCategory.food.rawValue,
                            spentOn: trip.departDate ?? Date(), status: .purchased,
                            purchasedFrom: storeName)
            sheet = .expense(e)
        }
    }

    @ViewBuilder
    private func header(for group: ShopPrimaryGroup) -> some View {
        HStack(spacing: 6) {
            Image(systemName: group.icon).font(.footnote)
            Text(group.title).font(.subheadline.weight(.semibold))
            Text("· \(group.allItems.count)").font(.caption).opacity(0.7)
            Spacer()
            if mode == .expenses, let total = TripFormat.money(groupTotal(group.allItems)) {
                Text(total).font(.subheadline.weight(.semibold))
            }
            Button {
                addItem(category: grouping == .category ? group.title : group.allItems.first?.category,
                        store: grouping == .store ? group.title : storeFilter)
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
        .contextMenu {
            if mode == .shopping {
                Button("Mark all purchased", systemImage: "checkmark.circle") { markAllPurchased(group) }
            } else {
                Button("Move all to shopping", systemImage: "cart") { moveAllToShopping(group) }
            }
            Button("Add to \(group.title)", systemImage: "plus") {
                addItem(category: grouping == .category ? group.title : group.allItems.first?.category,
                        store: grouping == .store ? group.title : storeFilter)
            }
        }
        .dropDestination(for: String.self) { ids, _ in
            Task { await moveItems(ids, toPrimary: group) }
            return true
        } isTargeted: { dropTargetTitle = $0 ? group.title : nil }
    }

    private func subHeader(_ sub: ShopSubGroup, in group: ShopPrimaryGroup, color: Color) -> some View {
        let key = "\(group.title)|\(sub.title ?? "")"
        return HStack(spacing: 6) {
            if let icon = sub.icon { Image(systemName: icon).font(.caption2) }
            Text(sub.title ?? "").font(.caption.weight(.semibold)).textCase(.uppercase).kerning(0.4)
            Text("· \(sub.items.count)").font(.caption2).opacity(0.7)
            Spacer()
            if mode == .expenses, let total = TripFormat.money(groupTotal(sub.items)) {
                Text(total).font(.caption.weight(.semibold))
            }
            Button {
                addItem(category: sub.items.first?.category, store: sub.items.first?.purchasedFrom)
            } label: {
                Image(systemName: "plus.circle").font(.caption)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Add to \(sub.title ?? "")")
        }
        .foregroundStyle(color)
        .padding(.leading, 6)
        .padding(.vertical, 2)
        .background(dropTargetTitle == key ? color.opacity(0.18) : Color.clear,
                    in: RoundedRectangle(cornerRadius: 6))
        .listRowSeparator(.hidden)
        .contentShape(Rectangle())
        // Drop an item here to move it into this primary + sub-group.
        .dropDestination(for: String.self) { ids, _ in
            Task { await moveItems(ids, into: group, sub: sub) }
            return true
        } isTargeted: { dropTargetTitle = $0 ? key : nil }
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

    private func setDimension(_ dim: Grouping, on item: inout Expense, to title: String) {
        switch dim {
        case .category: item.category = title
        case .store:    item.purchasedFrom = (title == Self.noWhere) ? nil : title
        }
    }

    private func setItemCategory(_ item: Expense, _ c: String) async {
        var u = item; u.category = c
        await store.saveExpense(u, splits: store.splits(for: u))
    }

    private func setItemWhere(_ item: Expense, _ w: String?) async {
        var u = item; u.purchasedFrom = w
        await store.saveExpense(u, splits: store.splits(for: u))
    }

    /// Drop an item's card directly onto another item — it adopts that item's
    /// bucket(s), so the whole group is a drop target (not just the header).
    private func moveItems(_ ids: [String], ontoItemLike target: Expense) async {
        for id in ids where id != target.id.uuidString {
            guard let item = sourceItems.first(where: { $0.id.uuidString == id }) else { continue }
            var updated = item
            if grouping == .category {
                updated.category = target.category
                if activeSub != nil { updated.purchasedFrom = target.purchasedFrom }
            } else {
                updated.purchasedFrom = target.purchasedFrom
                if activeSub != nil { updated.category = target.category }
            }
            // Skip a no-op drop (onto a sibling already in the same bucket).
            guard updated.category != item.category || updated.purchasedFrom != item.purchasedFrom else { continue }
            await store.saveExpense(updated, splits: store.splits(for: updated))
        }
    }

    /// Drop onto a primary header — set the primary dimension to match.
    private func moveItems(_ ids: [String], toPrimary group: ShopPrimaryGroup) async {
        for id in ids {
            guard let item = sourceItems.first(where: { $0.id.uuidString == id }) else { continue }
            var updated = item
            setDimension(grouping, on: &updated, to: group.title)
            await store.saveExpense(updated, splits: store.splits(for: updated))
        }
    }

    /// Drop onto a sub-header — place the item in BOTH the primary group and the
    /// sub-group it was dropped into.
    private func moveItems(_ ids: [String], into group: ShopPrimaryGroup, sub: ShopSubGroup) async {
        guard let subDim = activeSub, let sTitle = sub.title else { return }
        for id in ids {
            guard let item = sourceItems.first(where: { $0.id.uuidString == id }) else { continue }
            var updated = item
            setDimension(grouping, on: &updated, to: group.title)
            setDimension(subDim, on: &updated, to: sTitle)
            await store.saveExpense(updated, splits: store.splits(for: updated))
        }
    }
}
