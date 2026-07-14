import SwiftUI

/// The Shopping view — items still to buy (unified `fam_trip_expenses` rows with
/// a non-purchased status). Checking one off marks it purchased, moving it into
/// Expenses and the budget.
struct TripPurchasesSection: View {
    let store: TripDetailStore
    let familyID: UUID
    @Environment(FamilyStore.self) private var family
    @State private var editing: Expense?

    private static let defaultTags = ["Food / Kitchen", "Gear / Tools", "Clothing", "Toiletries", "Other"]

    private func newItem() -> Expense {
        Expense(tripID: store.tripID, category: ExpenseCategory.merch.rawValue, status: .notPurchased)
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

                ForEach(store.shoppingByTag, id: \.tag) { group in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(group.tag).font(.subheadline.bold()).foregroundStyle(.secondary)
                        ForEach(group.items) { item in
                            PurchaseRow(item: item,
                                        onToggle: { Task { await store.togglePurchased(item, defaultPayer: family.currentMember?.id) } },
                                        onEdit: { editing = item })
                                .contextMenu {
                                    Button("Edit") { editing = item }
                                    Button("Delete", role: .destructive) { Task { await store.deleteExpense(item) } }
                                }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .sheet(item: $editing) { p in
            PurchaseEditView(store: store, item: p,
                             tagOptions: (Set(Self.defaultTags).union(store.shoppingTags)).sorted())
        }
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
    @Environment(FamilyStore.self) private var family
    @Environment(\.dismiss) private var dismiss

    @State private var draft: Expense
    @State private var amountText: String
    @State private var tagText: String
    let tagOptions: [String]

    init(store: TripDetailStore, item: Expense, tagOptions: [String]) {
        self.store = store
        self.tagOptions = tagOptions
        _draft = State(initialValue: item)
        _amountText = State(initialValue: item.amount == 0 ? "" : String(format: "%.2f", item.amount))
        _tagText = State(initialValue: item.tag ?? "")
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
                Section("Details") {
                    TextField("Amount (USD)", text: $amountText)
                        #if !targetEnvironment(macCatalyst)
                        .keyboardType(.decimalPad)
                        #endif
                    TextField("From (store / site)", text: Binding(
                        get: { draft.purchasedFrom ?? "" }, set: { draft.purchasedFrom = $0.nilIfBlank }))
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
