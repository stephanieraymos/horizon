import SwiftUI

struct TripPackingSection: View {
    let store: TripDetailStore
    @Environment(FamilyStore.self) private var family
    @State private var grouping: Grouping = .person
    @State private var showAdd = false

    enum Grouping: String, CaseIterable { case person = "Person", category = "Category" }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Packing").font(.title3.bold())
                Spacer()
                Button { showAdd = true } label: { Image(systemName: "plus.circle.fill").font(.title3) }
                    .tint(Theme.Colors.brand)
            }

            if store.packing.isEmpty {
                Text("Nothing packed yet. Add items per person and category.")
                    .font(.callout).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding().background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 12))
            } else {
                Picker("Group by", selection: $grouping) {
                    ForEach(Grouping.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)

                ForEach(groups, id: \.title) { group in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(group.title).font(.subheadline.bold()).foregroundStyle(.secondary)
                        ForEach(group.items) { item in
                            PackingRow(item: item) { Task { await store.togglePacking(item) } }
                                .contextMenu {
                                    Button("Delete", role: .destructive) {
                                        Task { await store.deletePacking(item) }
                                    }
                                }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .sheet(isPresented: $showAdd) {
            PackingAddView(store: store)
        }
    }

    private var groups: [(title: String, items: [PackingItem])] {
        switch grouping {
        case .person:
            return Dictionary(grouping: store.packing, by: \.memberID)
                .map { (family.memberName(id: $0.key) ?? "Someone", $0.value.sorted { $0.item < $1.item }) }
                .sorted { $0.0 < $1.0 }
                .map { (title: $0.0, items: $0.1) }
        case .category:
            return Dictionary(grouping: store.packing, by: { $0.category ?? .other })
                .map { ($0.key.label, $0.value.sorted { $0.item < $1.item }) }
                .sorted { $0.0 < $1.0 }
                .map { (title: $0.0, items: $0.1) }
        }
    }
}

private struct PackingRow: View {
    let item: PackingItem
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 10) {
                Image(systemName: item.checked ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(item.checked ? Theme.Colors.brand : .secondary)
                Text(item.item)
                    .strikethrough(item.checked)
                    .foregroundStyle(item.checked ? .secondary : .primary)
                Spacer()
                if let cat = item.category {
                    Label(cat.label, systemImage: cat.systemImage)
                        .labelStyle(.iconOnly).foregroundStyle(.secondary).font(.caption)
                }
            }
        }
        .buttonStyle(.plain)
        .padding(.vertical, 4)
    }
}

private struct PackingAddView: View {
    let store: TripDetailStore
    @Environment(FamilyStore.self) private var family
    @Environment(\.dismiss) private var dismiss

    @State private var memberID: UUID?
    @State private var item = ""
    @State private var category: PackingCategory = .clothes

    var body: some View {
        NavigationStack {
            Form {
                Picker("For", selection: $memberID) {
                    Text("Choose…").tag(UUID?.none)
                    ForEach(family.members) { Text($0.name).tag(UUID?.some($0.id)) }
                }
                TextField("Item", text: $item)
                Picker("Category", selection: $category) {
                    ForEach(PackingCategory.allCases, id: \.self) {
                        Label($0.label, systemImage: $0.systemImage).tag($0)
                    }
                }
            }
            .navigationTitle("Add Item")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        guard let memberID else { return }
                        let new = PackingItem(tripID: store.tripID, memberID: memberID,
                                              item: item, category: category)
                        Task { await store.savePacking(new); dismiss() }
                    }
                    .disabled(memberID == nil || item.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear { if memberID == nil { memberID = family.currentMember?.id } }
        }
    }
}
