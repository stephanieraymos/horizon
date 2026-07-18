import SwiftUI

/// Compact shopping summary on the trip detail — count + estimate and a per-tag
/// snapshot, opening the full grouped shopping list.
struct TripPurchasesSection: View {
    let store: TripDetailStore
    let trip: Trip
    let familyID: UUID

    /// Per-tag "count" for a quick glance.
    private var perTag: [(tag: String, count: Int)] {
        store.shoppingByTag.map { (tag: $0.tag, count: $0.items.count) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Shopping").font(.title3.bold())

            NavigationLink {
                ShoppingListView(store: store, trip: trip, familyID: familyID)
            } label: {
                VStack(alignment: .leading, spacing: 10) {
                    if store.shoppingItems.isEmpty {
                        Text("Build a shopping list for this trip. Tap to add items and check them off.")
                            .font(.callout).foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        HStack {
                            Label("\(store.shoppingToBuyCount) to buy", systemImage: "cart")
                                .font(.subheadline.weight(.medium))
                            Spacer()
                            if let est = TripFormat.money(store.shoppingProjected), store.shoppingProjected > 0 {
                                Text("\(est) est.").font(.subheadline).foregroundStyle(.secondary)
                            }
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                        }
                        if !perTag.isEmpty {
                            FlowLayout(spacing: 6) {
                                ForEach(perTag, id: \.tag) { row in
                                    Text("\(row.tag) \(row.count)")
                                        .font(.caption)
                                        .padding(.horizontal, 8).padding(.vertical, 3)
                                        .background(Color(.tertiarySystemFill), in: Capsule())
                                        .foregroundStyle(.secondary)
                                }
                            }
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
    let onToggle: () -> Void
    let onEdit: () -> Void
    @Environment(FamilyStore.self) private var family

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
                        if let by = item.loggedBy, let name = family.memberName(id: by) {
                            Text("Added by \(name)").font(.caption2).foregroundStyle(.tertiary)
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

struct PurchaseEditView: View {
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
