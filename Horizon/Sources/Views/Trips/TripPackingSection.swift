import SwiftUI

/// Compact packing summary on the trip detail — progress + a per-person snapshot,
/// opening the full filterable packing list.
struct TripPackingSection: View {
    let store: TripDetailStore
    let trip: Trip
    @Environment(FamilyStore.self) private var family

    private var packed: Int { store.packing.filter(\.checked).count }
    private var total: Int { store.packing.count }

    /// Per-person "packed/total" for a quick glance.
    private var perPerson: [(name: String, packed: Int, total: Int)] {
        Dictionary(grouping: store.packing, by: \.memberID)
            .map { (family.memberName(id: $0.key) ?? "Someone",
                    $0.value.filter(\.checked).count, $0.value.count) }
            .sorted { $0.0 < $1.0 }
            .map { (name: $0.0, packed: $0.1, total: $0.2) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Packing").font(.title3.bold())

            NavigationLink {
                PackingListView(store: store, trip: trip)
            } label: {
                VStack(alignment: .leading, spacing: 10) {
                    if total == 0 {
                        Text("Nothing packed yet. Tap to add items or apply a template.")
                            .font(.callout).foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        HStack {
                            Text("\(packed) of \(total) packed").font(.subheadline.weight(.medium))
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                        }
                        ProgressView(value: total == 0 ? 0 : Double(packed) / Double(total))
                            .tint(Theme.Colors.brand)
                        if !perPerson.isEmpty {
                            FlowLayout(spacing: 6) {
                                ForEach(perPerson, id: \.name) { row in
                                    Text("\(row.name.split(separator: " ").first.map(String.init) ?? row.name) \(row.packed)/\(row.total)")
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
