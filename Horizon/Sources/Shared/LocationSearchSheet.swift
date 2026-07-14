import SwiftUI
import MapKit

// MARK: - Result type

struct LocationResult {
    var name: String
    var address: String
    var mapsURL: String
}

// MARK: - Completer observable

@MainActor
final class LocationCompleter: NSObject, ObservableObject, MKLocalSearchCompleterDelegate {
    @Published var completions: [MKLocalSearchCompletion] = []
    @Published var isSearching = false

    private let completer = MKLocalSearchCompleter()

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = [.query, .address]
    }

    func update(query: String) {
        if query.trimmingCharacters(in: .whitespaces).isEmpty {
            completions = []
            isSearching = false
        } else {
            isSearching = true
            completer.queryFragment = query
        }
    }

    // MapKit delivers completer callbacks on the main queue, so we can read the
    // non-Sendable results directly on the main actor instead of sending them
    // across an actor boundary (which Swift 6 strict concurrency rejects).
    nonisolated func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        MainActor.assumeIsolated {
            self.completions = self.completer.results
            self.isSearching = false
        }
    }

    nonisolated func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        MainActor.assumeIsolated {
            self.isSearching = false
        }
    }
}

// MARK: - Sheet view

/// Present this sheet when the user wants to pick a real location. `onSelect`
/// is called on the main thread with the chosen result (name + address + an
/// Apple Maps URL).
struct LocationSearchSheet: View {
    let onSelect: (LocationResult) -> Void

    @Environment(\.dismiss) private var dismiss
    @StateObject private var completer = LocationCompleter()
    @State private var query = ""
    @State private var isResolving = false
    /// When a completion resolves to multiple nearby candidates, we hold them
    /// here and show a second picker instead of auto-selecting the first.
    @State private var candidates: [MKMapItem] = []
    @State private var pendingCompletion: MKLocalSearchCompletion? = nil

    var body: some View {
        NavigationStack {
            List {
                if !candidates.isEmpty {
                    // Second level: user picks the specific location from nearby results
                    Section("Nearby results") {
                        ForEach(candidates.indices, id: \.self) { idx in
                            let item = candidates[idx]
                            Button {
                                pick(item)
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.name ?? "Unknown")
                                        .font(.body)
                                        .foregroundStyle(.primary)
                                    let addr = buildAddress(from: item.placemark)
                                    if !addr.isEmpty {
                                        Text(addr)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .padding(.vertical, 2)
                            }
                        }
                    }
                } else if completer.completions.isEmpty && !query.isEmpty && !completer.isSearching {
                    ContentUnavailableView.search(text: query)
                } else {
                    ForEach(completer.completions, id: \.self) { completion in
                        Button {
                            resolve(completion)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(completion.title)
                                    .font(.body)
                                    .foregroundStyle(.primary)
                                if !completion.subtitle.isEmpty {
                                    Text(completion.subtitle)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(.vertical, 2)
                        }
                        .disabled(isResolving)
                    }
                }
            }
            .listStyle(.plain)
            .overlay {
                if isResolving {
                    ProgressView("Looking up location…")
                        .padding()
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search for a place")
            .onChange(of: query) { _, newValue in
                candidates = []
                completer.update(query: newValue)
            }
            .navigationTitle(candidates.isEmpty ? "Find a Location" : "Choose a Location")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if candidates.isEmpty {
                        Button("Cancel") { dismiss() }
                    } else {
                        Button("Back") { candidates = [] }
                    }
                }
            }
        }
    }

    private func resolve(_ completion: MKLocalSearchCompletion) {
        isResolving = true
        pendingCompletion = completion
        let request = MKLocalSearch.Request(completion: completion)
        let search = MKLocalSearch(request: request)
        search.start { response, _ in
            Task { @MainActor in
                defer { isResolving = false }
                let items = response?.mapItems ?? []
                if !items.isEmpty {
                    // Always show the candidate list so the user confirms
                    // the right location — never auto-select.
                    candidates = items
                } else {
                    // No map data — synthesise a single result from the
                    // completion text so the user can still save it.
                    let address = completion.subtitle.isEmpty ? "" : completion.subtitle
                    let encoded = completion.title.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
                    onSelect(LocationResult(
                        name: completion.title,
                        address: address,
                        mapsURL: "https://maps.apple.com/?q=\(encoded)"
                    ))
                    dismiss()
                }
            }
        }
    }

    private func pick(_ item: MKMapItem) {
        let name = item.name ?? (pendingCompletion?.title ?? "Location")
        let address = buildAddress(from: item.placemark)
        let mapsURL = buildMapsURL(from: item)
        onSelect(LocationResult(name: name, address: address, mapsURL: mapsURL))
        dismiss()
    }

    private func buildAddress(from placemark: MKPlacemark) -> String {
        // subThoroughfare = street number ("123"), thoroughfare = street name ("Main St")
        let streetNumber = placemark.subThoroughfare ?? ""
        let streetName   = placemark.thoroughfare ?? ""
        let street: String? = {
            if streetNumber.isEmpty && streetName.isEmpty { return nil }
            if streetNumber.isEmpty { return streetName }
            if streetName.isEmpty   { return streetNumber }
            return "\(streetNumber) \(streetName)"
        }()
        return [street, placemark.locality, placemark.administrativeArea, placemark.postalCode]
            .compactMap { $0 }
            .joined(separator: ", ")
    }

    private func buildMapsURL(from item: MKMapItem) -> String {
        let coord = item.placemark.coordinate
        let encoded = (item.name ?? "").addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        return "https://maps.apple.com/?q=\(encoded)&ll=\(coord.latitude),\(coord.longitude)"
    }
}
