import SwiftUI

struct TripPurchasesSection: View {
    let store: TripDetailStore
    let familyID: UUID
    @State private var editing: TripPurchase?

    private static let defaultTags = ["Food / Kitchen", "Gear / Tools", "Clothing", "Toiletries", "Other"]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Shopping").font(.title3.bold())
                Spacer()
                Button { editing = TripPurchase(familyID: familyID, tripID: store.tripID) } label: {
                    Image(systemName: "plus.circle.fill").font(.title3)
                }
                .tint(Theme.Colors.brand)
            }

            if store.purchases.isEmpty {
                Text("Build a shopping list for this trip.")
                    .font(.callout).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding().background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 12))
            } else {
                HStack {
                    Label("\(store.purchasesToBuy) to buy", systemImage: "cart")
                    Spacer()
                    if let spent = TripFormat.money(store.purchasesSpent), store.purchasesSpent > 0 {
                        Text("\(spent) purchased").foregroundStyle(.secondary)
                    }
                }
                .font(.subheadline)
                .padding().background(Theme.Colors.brand.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))

                ForEach(store.purchasesByTag, id: \.tag) { group in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(group.tag).font(.subheadline.bold()).foregroundStyle(.secondary)
                        ForEach(group.items) { item in
                            PurchaseRow(item: item,
                                        onToggle: { Task { await store.cyclePurchase(item) } },
                                        onEdit: { editing = item })
                                .contextMenu {
                                    Button("Edit") { editing = item }
                                    Button("Delete", role: .destructive) { Task { await store.deletePurchase(item) } }
                                }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .sheet(item: $editing) { p in
            PurchaseEditView(store: store, purchase: p,
                             tagOptions: (Set(Self.defaultTags).union(store.purchaseTags)).sorted())
        }
    }
}

private struct PurchaseRow: View {
    let item: TripPurchase
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
                    }
                    Spacer()
                    if let amt = TripFormat.money(item.amountDollars) {
                        Text(amt).font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 3)
    }
}

private struct PurchaseEditView: View {
    let store: TripDetailStore
    @Environment(\.dismiss) private var dismiss

    @State private var draft: TripPurchase
    @State private var amountText: String
    @State private var tagText: String
    let tagOptions: [String]

    init(store: TripDetailStore, purchase: TripPurchase, tagOptions: [String]) {
        self.store = store
        self.tagOptions = tagOptions
        _draft = State(initialValue: purchase)
        _amountText = State(initialValue: purchase.amountCents.map { String(format: "%.2f", Double($0) / 100) } ?? "")
        _tagText = State(initialValue: purchase.tag ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Item", text: $draft.name)
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
                }
            }
            .navigationTitle(draft.name.isEmpty ? "New Item" : "Edit Item")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await save() } }
                        .disabled(draft.name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private func save() async {
        draft.tag = tagText.nilIfBlank
        draft.amountCents = Double(amountText.replacingOccurrences(of: ",", with: "")).map { Int(($0 * 100).rounded()) }
        await store.savePurchase(draft)
        dismiss()
    }
}
