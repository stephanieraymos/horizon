import SwiftUI
import Charts

/// The spend summary shown atop the unified Money page in Expenses mode:
/// spent-so-far + budget, a by-category bar chart, per-member totals, and the
/// who-owes-whom settle-up. (Shopping mode hides all of this.)
struct ExpenseSummaryView: View {
    let store: TripDetailStore
    let trip: Trip
    @Environment(FamilyStore.self) private var family

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            summary
            if categoryTotals.count > 1 { categoryChart }
        }
    }

    private var categoryTotals: [(category: String, total: Double)] {
        Dictionary(grouping: store.purchasedExpenses, by: \.category)
            .map { (category: $0.key, total: $0.value.reduce(0) { $0 + $1.amount }) }
            .sorted { $0.total > $1.total }
    }

    private var categoryChart: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("By category").font(.subheadline.bold()).foregroundStyle(.secondary)
            Chart(categoryTotals, id: \.category) { row in
                BarMark(
                    x: .value("Amount", row.total),
                    y: .value("Category", row.category))
                .foregroundStyle(Theme.Colors.brand.gradient)
                .annotation(position: .trailing, alignment: .leading) {
                    Text(TripFormat.money(row.total) ?? "").font(.caption2).foregroundStyle(.secondary)
                }
            }
            .chartXAxis(.hidden)
            .frame(height: CGFloat(categoryTotals.count) * 34 + 10)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Spent so far").font(.subheadline).foregroundStyle(.secondary)
                Spacer()
                Text(TripFormat.money(store.tripTotal) ?? "$0").font(.headline)
            }
            if store.shoppingProjected > 0 {
                HStack {
                    Text("Projected (with to-buy)").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Text(TripFormat.money(store.projectedTotal) ?? "$0")
                        .font(.caption.weight(.medium)).foregroundStyle(.secondary)
                }
            }
            if let top = categoryTotals.first, top.total > 0 {
                HStack(spacing: 4) {
                    Image(systemName: ExpenseCategory.icon(for: top.category)).font(.caption2)
                    Text("Most on \(top.category)").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Text(TripFormat.money(top.total) ?? "$0").font(.caption.weight(.medium)).foregroundStyle(.secondary)
                }
            }

            if let budget = trip.budget, budget > 0 {
                let frac = min(store.tripTotal / budget, 1)
                let over = store.tripTotal > budget
                ProgressView(value: frac)
                    .tint(over ? .red : Theme.Colors.brand)
                HStack {
                    Text("\(TripFormat.money(store.tripTotal) ?? "$0") of \(TripFormat.money(budget) ?? "$0")")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Text(over ? "Over by \(TripFormat.money(store.tripTotal - budget) ?? "")"
                              : "\(TripFormat.money(budget - store.tripTotal) ?? "") left")
                        .font(.caption).foregroundStyle(over ? .red : .secondary)
                }
            }

            if !store.perMemberTotals.isEmpty {
                Divider()
                ForEach(store.perMemberTotals, id: \.memberID) { row in
                    HStack {
                        Text(family.memberName(id: row.memberID) ?? "Someone").font(.callout)
                        Spacer()
                        Text(TripFormat.money(row.amount) ?? "$0").font(.callout).foregroundStyle(.secondary)
                    }
                }
            }

            let transfers = store.settleUp()
            if !transfers.isEmpty {
                Divider()
                Text("Settle up").font(.caption.bold()).foregroundStyle(.secondary)
                ForEach(Array(transfers.enumerated()), id: \.offset) { _, t in
                    HStack(spacing: 4) {
                        Text(family.memberName(id: t.from) ?? "Someone").fontWeight(.medium)
                        Image(systemName: "arrow.right").font(.caption2).foregroundStyle(.secondary)
                        Text(family.memberName(id: t.to) ?? "Someone").fontWeight(.medium)
                        Spacer()
                        Text(TripFormat.money(t.amount) ?? "$0").foregroundStyle(Theme.Colors.brand)
                    }
                    .font(.callout)
                }
            }
        }
        .padding().background(Theme.Colors.brand.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
    }
}

/// Full expense editor (paid-by + splits) — reached by tapping a row in Expenses
/// mode. Shopping-mode rows use the lighter `PurchaseEditView`.
struct ExpenseEditView: View {
    let store: TripDetailStore
    @Environment(FamilyStore.self) private var family
    @Environment(\.dismiss) private var dismiss
    @Environment(TripsStore.self) private var trips

    @State private var draft: Expense
    @State private var amountText: String
    @State private var spentOn: Date
    @State private var category: String
    @State private var whereText: String
    @State private var involved: Set<UUID>
    @State private var shares: [UUID: String]
    @State private var isSaving = false

    let travelerNames: [String]

    /// Only people on this trip can pay for or share an expense (falls back to the
    /// whole family if the trip has no travelers set yet).
    private var eligibleMembers: [FamilyMember] {
        let names = Set(travelerNames.map { $0.lowercased() })
        let filtered = family.members.filter { names.contains($0.name.lowercased()) }
        return filtered.isEmpty ? family.members : filtered
    }

    init(store: TripDetailStore, expense: Expense, travelerNames: [String]) {
        self.store = store
        self.travelerNames = travelerNames
        _draft = State(initialValue: expense)
        _amountText = State(initialValue: expense.amount > 0 ? String(format: "%.2f", expense.amount) : "")
        _spentOn = State(initialValue: expense.spentOn ?? Date())
        _category = State(initialValue: expense.category)
        _whereText = State(initialValue: expense.purchasedFrom ?? "")
        let existing = store.splits(for: expense)
        _involved = State(initialValue: Set(existing.map(\.memberID)))
        _shares = State(initialValue: Dictionary(uniqueKeysWithValues:
            existing.map { ($0.memberID, String(format: "%.2f", $0.amount)) }))
    }

    private var total: Double { Double(amountText.replacingOccurrences(of: ",", with: "")) ?? 0 }
    private var splitSum: Double { involved.reduce(0) { $0 + (Double(shares[$1] ?? "") ?? 0) } }
    private var remaining: Double { total - splitSum }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ComboField(placeholder: "Category", text: $category,
                               options: categoryOptions, pickIcon: "tag")
                    TextField("Description", text: Binding(
                        get: { draft.description ?? "" }, set: { draft.description = $0.nilIfBlank }))
                    TextField("Amount (USD)", text: $amountText)
                        #if !targetEnvironment(macCatalyst)
                        .keyboardType(.decimalPad)
                        #endif
                    DatePicker("Date", selection: $spentOn, displayedComponents: .date)
                    // Shared "Where" list with Shopping (fam_shopping_stores), so a
                    // vendor typed once autocompletes in both places.
                    ComboField(placeholder: "Where (optional)", text: $whereText,
                               options: trips.shoppingStores.map { .init(id: $0.id.uuidString, name: $0.name, icon: "mappin.and.ellipse") },
                               pickIcon: "mappin.and.ellipse",
                               onAdd: { name in
                                   if let fid = family.familyID {
                                       Task { await trips.createShoppingStore(familyID: fid, name: name) }
                                   }
                               })
                    Picker("Paid by", selection: $draft.paidBy) {
                        Text("—").tag(UUID?.none)
                        ForEach(eligibleMembers) { Text($0.name).tag(UUID?.some($0.id)) }
                    }
                }

                Section {
                    ForEach(eligibleMembers) { member in
                        HStack {
                            Button {
                                toggle(member.id)
                            } label: {
                                Image(systemName: involved.contains(member.id) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(involved.contains(member.id) ? Theme.Colors.brand : .secondary)
                            }
                            .buttonStyle(.plain)
                            Text(member.name)
                            Spacer()
                            if involved.contains(member.id) {
                                TextField("0.00", text: Binding(
                                    get: { shares[member.id] ?? "" },
                                    set: { shares[member.id] = $0 }))
                                    .multilineTextAlignment(.trailing)
                                    .frame(width: 80)
                                    #if !targetEnvironment(macCatalyst)
                                    .keyboardType(.decimalPad)
                                    #endif
                            }
                        }
                    }
                } header: {
                    HStack {
                        Text("Split")
                        Spacer()
                        Button("Split evenly") { splitEvenly() }.font(.caption)
                    }
                } footer: {
                    if !involved.isEmpty {
                        Text(remaining == 0 ? "Fully allocated"
                             : "Unallocated: \(TripFormat.money(remaining) ?? "$0")")
                            .foregroundStyle(abs(remaining) < 0.01 ? Color.secondary : Color.orange)
                    }
                }
            }
            .navigationTitle("Expense")
            .onAppear {
                // Default the payer to the current member (usually the payer).
                if draft.paidBy == nil { draft.paidBy = family.currentMember?.id }
            }
            .interactiveDismissDisabled(isSaving)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button("Save") { isSaving = true; Task { await save() } }
                            .disabled(total <= 0)
                    }
                }
            }
        }
    }

    private var categoryOptions: [ComboField.Option] {
        let used = Set(store.expenses.map(\.category))
        return Set(ExpenseCategory.allCases.map(\.rawValue)).union(used).sorted()
            .map { .init(id: $0, name: $0, icon: ExpenseCategory.icon(for: $0)) }
    }

    private func toggle(_ id: UUID) {
        if involved.contains(id) { involved.remove(id); shares[id] = nil }
        else { involved.insert(id) }
    }

    private func splitEvenly() {
        guard !involved.isEmpty, total > 0 else { return }
        let each = (total / Double(involved.count) * 100).rounded() / 100
        for id in involved { shares[id] = String(format: "%.2f", each) }
    }

    private func save() async {
        draft.amount = total
        draft.category = category
        draft.spentOn = spentOn
        draft.purchasedFrom = whereText.nilIfBlank
        // "Where" (purchased_from) is now the source of truth; drop the legacy
        // fam_places link so it can't drift out of sync with the visible value.
        draft.placeID = nil
        // Persist a brand-new vendor to the shared list so it's reusable.
        if let name = whereText.nilIfBlank, trips.store(named: name) == nil, let fid = family.familyID {
            await trips.createShoppingStore(familyID: fid, name: name)
        }
        if draft.loggedBy == nil { draft.loggedBy = family.currentMember?.id }
        let newSplits: [ExpenseSplit] = involved.compactMap { id in
            let amt = Double(shares[id] ?? "") ?? 0
            guard amt > 0 else { return nil }
            return ExpenseSplit(expenseID: draft.id, memberID: id, amount: amt)
        }
        await store.saveExpense(draft, splits: newSplits)
        dismiss()
    }
}
