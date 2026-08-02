import SwiftUI

/// Links attached to an event/trip (venue page, registry, menu, tickets…),
/// stored in the shared `tm_links` table with `type = ["event"]`.
struct TripLinksSection: View {
    let store: TripDetailStore
    var kind: PlanKind = .trip

    @Environment(\.openURL) private var openURL
    @State private var showAdd = false
    @AppStorage private var collapsed: Bool

    init(store: TripDetailStore, kind: PlanKind = .trip) {
        self.store = store
        self.kind = kind
        _collapsed = AppStorage(wrappedValue: false, "trip.links.collapsed.\(store.tripID.uuidString)")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Button { withAnimation(.snappy) { collapsed.toggle() } } label: {
                    HStack(spacing: 6) {
                        Text("Links").font(.title3.bold())
                        Image(systemName: collapsed ? "chevron.right" : "chevron.down")
                            .font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
                if !store.links.isEmpty {
                    Text("\(store.links.count)")
                        .font(.caption).foregroundStyle(.secondary)
                        .padding(.horizontal, 8).padding(.vertical, 2)
                        .background(Color(.tertiarySystemFill), in: Capsule())
                }
                Spacer()
                Button { showAdd = true } label: {
                    Image(systemName: "plus.circle.fill").font(.title3)
                }
                .tint(Theme.Colors.brand)
            }

            if !collapsed {
                if store.links.isEmpty {
                    Text("Add links — the venue page, registry, menu, tickets, or directions.")
                        .font(.callout).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding().background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 12))
                } else {
                    ForEach(store.links) { link in
                        Button { if let u = link.openURL { openURL(u) } } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "link")
                                    .foregroundStyle(Theme.Colors.brand).frame(width: 20)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(link.displayTitle).font(.subheadline.weight(.medium))
                                        .foregroundStyle(.primary).lineLimit(1)
                                    if let host = link.openURL?.host {
                                        Text(host).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                    }
                                }
                                Spacer()
                                Image(systemName: "arrow.up.right").font(.caption2).foregroundStyle(.tertiary)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .padding(.vertical, 3)
                        .contextMenu {
                            Button("Delete", role: .destructive) { Task { await store.deleteLink(link) } }
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showAdd) {
            AddLinkView(store: store)
        }
    }
}

private struct AddLinkView: View {
    let store: TripDetailStore
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var url = ""
    @State private var isSaving = false

    var body: some View {
        NavigationStack {
            Form {
                TextField("Title (optional)", text: $title)
                TextField("URL", text: $url)
                    .textContentType(.URL)
                    .autocorrectionDisabled()
                    #if os(iOS)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    #endif
            }
            .navigationTitle("Add Link")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button("Add") {
                            isSaving = true
                            Task { await store.addLink(title: title, url: url); dismiss() }
                        }
                        .disabled(url.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
        }
    }
}
