import SwiftUI

/// One combined "Money" card on the trip detail — spent-so-far + budget on top,
/// to-buy count below — opening the unified Shopping / Expenses page.
struct TripMoneySection: View {
    let store: TripDetailStore
    let trip: Trip
    let familyID: UUID

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Money").font(.title3.bold())

            NavigationLink {
                TripMoneyView(store: store, trip: trip, familyID: familyID)
            } label: {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Spent so far").font(.caption).foregroundStyle(.secondary)
                            Text(TripFormat.money(store.tripTotal) ?? "$0").font(.title3.bold())
                        }
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                    }

                    if let budget = trip.budget, budget > 0 {
                        let frac = min(store.tripTotal / budget, 1)
                        let over = store.tripTotal > budget
                        ProgressView(value: frac).tint(over ? .red : Theme.Colors.brand)
                        HStack {
                            Text("\(TripFormat.money(store.tripTotal) ?? "$0") of \(TripFormat.money(budget) ?? "$0")")
                                .font(.caption2).foregroundStyle(.secondary)
                            Spacer()
                            Text(over ? "Over by \(TripFormat.money(store.tripTotal - budget) ?? "")"
                                      : "\(TripFormat.money(budget - store.tripTotal) ?? "") left")
                                .font(.caption2).foregroundStyle(over ? .red : .secondary)
                        }
                    }

                    Divider()

                    HStack {
                        Label(store.shoppingItems.isEmpty ? "Build a shopping list"
                                                           : "\(store.shoppingToBuyCount) to buy",
                              systemImage: "cart")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(store.shoppingItems.isEmpty ? .secondary : .primary)
                        Spacer()
                        if store.shoppingProjected > 0, let est = TripFormat.money(store.shoppingProjected) {
                            Text("\(est) est.").font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
        }
    }
}

struct PurchaseRow: View {
    let item: Expense
    /// Tapping the checkbox toggles purchased (shopping list). Pass nil in the
    /// expense ledger so the leading glyph is an inert category icon — un-logging
    /// an expense there is a long-press "Move to shopping" instead of a stray tap.
    var onToggle: (() -> Void)? = nil
    /// Shopping mode strikes through purchased items (checked off the list); the
    /// expense ledger shows them as plain rows (everything there is purchased).
    var strikeWhenPurchased: Bool = true
    @Environment(FamilyStore.self) private var family

    var body: some View {
        // No Button wraps the row body — a full-row Button swallows the long-press
        // that `.draggable` needs, which broke drag-to-regroup. The caller adds the
        // tap-to-edit via `.onTapGesture`; only the checkbox stays a Button.
        HStack(spacing: 10) {
            if let onToggle {
                Button(action: onToggle) {
                    Image(systemName: item.status.systemImage)
                        .foregroundStyle(item.status == .purchased ? Theme.Colors.brand : .secondary)
                }
                .buttonStyle(.plain)
            } else {
                Image(systemName: ExpenseCategory.icon(for: item.category))
                    .foregroundStyle(.secondary)
                    .frame(width: 20)
            }

            VStack(alignment: .leading, spacing: 1) {
                // Expenses can be logged without a description; fall back to the
                // category so the ledger never shows a blank row.
                Text(item.name.nilIfBlank ?? item.category).lineLimit(1)
                    .strikethrough(strikeWhenPurchased && item.status == .purchased)
                    .foregroundStyle(strikeWhenPurchased && item.status == .purchased ? .secondary : .primary)
                if item.status == .inCart {
                    Text("In cart").font(.caption2).foregroundStyle(Theme.Colors.brand)
                } else if let from = item.purchasedFrom?.nilIfBlank {
                    Text(from).font(.caption2).foregroundStyle(.secondary)
                }
                if let notes = item.notes?.nilIfBlank {
                    Text(notes).font(.caption2).foregroundStyle(.tertiary).lineLimit(2)
                }
                if let by = item.loggedBy, let name = family.memberName(id: by) {
                    Text("Added by \(name)").font(.caption2).foregroundStyle(.tertiary)
                }
            }
            Spacer()
            if let amt = TripFormat.money(item.amountDollars) {
                Text(amt).font(.subheadline).foregroundStyle(.secondary)
            }
            if let url = item.linkURL {
                Link(destination: url) { Image(systemName: "link").font(.caption) }
                    .buttonStyle(.plain).foregroundStyle(Theme.Colors.brand)
            }
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
    }
}

struct PurchaseEditView: View {
    let store: TripDetailStore
    let familyID: UUID
    @Environment(FamilyStore.self) private var family
    @Environment(TripsStore.self) private var trips
    @Environment(\.dismiss) private var dismiss

    @State private var draft: Expense
    @State private var amountText: String
    @State private var categoryText: String
    @State private var storeText: String
    /// Shared category vocabulary (same values Expenses use), so a checked-off
    /// item logs under the category it was filed in — no more everything → Merch.
    let categoryOptions: [String]

    init(store: TripDetailStore, familyID: UUID, item: Expense, categoryOptions: [String]) {
        self.store = store
        self.familyID = familyID
        self.categoryOptions = categoryOptions
        _draft = State(initialValue: item)
        _amountText = State(initialValue: item.amount == 0 ? "" : String(format: "%.2f", item.amount))
        _categoryText = State(initialValue: item.category)
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
                Section("Category") {
                    ComboField(placeholder: "Search or add a category", text: $categoryText,
                               options: categoryOptions.map { .init(id: $0, name: $0, icon: ExpenseCategory.icon(for: $0)) },
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
        draft.category = categoryText.nilIfBlank ?? ExpenseCategory.other.rawValue
        draft.purchasedFrom = storeText.nilIfBlank
        // Persist a brand-new store name to the managed list so it's reusable.
        if let name = storeText.nilIfBlank, trips.store(named: name) == nil {
            await trips.createShoppingStore(familyID: familyID, name: name)
        }
        draft.amount = Double(amountText.replacingOccurrences(of: ",", with: "")) ?? 0
        // Record who added the item (the shopping flow never set this before).
        if draft.loggedBy == nil { draft.loggedBy = family.currentMember?.id }
        // Marking purchased here defaults the payer to the current member.
        if draft.isPurchased, draft.paidBy == nil {
            draft.paidBy = family.currentMember?.id
            if draft.spentOn == nil { draft.spentOn = Date() }
        }
        await store.saveExpense(draft, splits: store.splits(for: draft))
        dismiss()
    }
}
