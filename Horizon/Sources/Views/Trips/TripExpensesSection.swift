import SwiftUI

struct TripExpensesSection: View {
    let store: TripDetailStore
    let trip: Trip
    @Environment(FamilyStore.self) private var family
    @State private var editing: Expense?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Expenses").font(.title3.bold())
                Spacer()
                Button { editing = Expense(tripID: trip.id, spentOn: trip.departDate ?? Date()) } label: {
                    Image(systemName: "plus.circle.fill").font(.title3)
                }
                .tint(Theme.Colors.brand)
            }

            if store.expenses.isEmpty {
                Text("Log expenses and split them across who came along.")
                    .font(.callout).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding().background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 12))
            } else {
                summary
                ForEach(byCategory, id: \.category) { group in
                    VStack(alignment: .leading, spacing: 4) {
                        Label(group.category, systemImage: ExpenseCategory.icon(for: group.category))
                            .font(.subheadline.bold()).foregroundStyle(.secondary)
                        ForEach(group.items) { exp in
                            ExpenseRow(expense: exp, splitCount: store.splits(for: exp).count)
                                .onTapGesture { editing = exp }
                                .contextMenu {
                                    Button("Edit") { editing = exp }
                                    Button("Delete", role: .destructive) { Task { await store.deleteExpense(exp) } }
                                }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .sheet(item: $editing) { exp in
            ExpenseEditView(store: store, expense: exp)
        }
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Trip total").font(.subheadline).foregroundStyle(.secondary)
                Spacer()
                Text(TripFormat.money(store.tripTotal) ?? "$0").font(.headline)
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

            Divider()
            ForEach(store.perMemberTotals, id: \.memberID) { row in
                HStack {
                    Text(family.memberName(id: row.memberID) ?? "Someone").font(.callout)
                    Spacer()
                    Text(TripFormat.money(row.amount) ?? "$0").font(.callout).foregroundStyle(.secondary)
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

    private var byCategory: [(category: String, items: [Expense])] {
        Dictionary(grouping: store.expenses, by: \.category)
            .map { (category: $0.key, items: $0.value) }
            .sorted { $0.category < $1.category }
    }
}

private struct ExpenseRow: View {
    let expense: Expense
    let splitCount: Int

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(expense.description?.nilIfBlank ?? expense.category).font(.subheadline)
                if splitCount > 0 {
                    Text("Split \(splitCount) ways").font(.caption2).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Text(TripFormat.money(expense.amount) ?? "$0").font(.subheadline)
        }
        .padding(.vertical, 4)
    }
}

private struct ExpenseEditView: View {
    let store: TripDetailStore
    @Environment(FamilyStore.self) private var family
    @Environment(\.dismiss) private var dismiss
    @Environment(TripsStore.self) private var trips

    @State private var draft: Expense
    @State private var amountText: String
    @State private var spentOn: Date
    @State private var category: String
    @State private var placeText: String = ""
    @State private var involved: Set<UUID>
    @State private var shares: [UUID: String]

    init(store: TripDetailStore, expense: Expense) {
        self.store = store
        _draft = State(initialValue: expense)
        _amountText = State(initialValue: expense.amount > 0 ? String(format: "%.2f", expense.amount) : "")
        _spentOn = State(initialValue: expense.spentOn ?? Date())
        _category = State(initialValue: expense.category)
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
                    PlaceComboField(placeholder: "Place (optional)", text: $placeText, placeID: $draft.placeID)
                    Picker("Paid by", selection: $draft.paidBy) {
                        Text("—").tag(UUID?.none)
                        ForEach(family.members) { Text($0.name).tag(UUID?.some($0.id)) }
                    }
                }

                Section {
                    ForEach(family.members) { member in
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
                if let pid = draft.placeID, let p = trips.places.first(where: { $0.id == pid }) {
                    placeText = p.name
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await save() } }
                        .disabled(total <= 0)
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
        if placeText.nilIfBlank == nil { draft.placeID = nil }  // don't keep a link to a cleared place
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
