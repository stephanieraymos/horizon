import SwiftUI
import MapKit
import CoreLocation

struct TripMapPin: Identifiable {
    let id = UUID()
    let name: String
    let coordinate: CLLocationCoordinate2D
    let systemImage: String
}

/// Geocodes a set of addresses and drops pins on a MapKit map. Renders nothing
/// until at least one address resolves, so trips without addresses show no map.
struct TripMapView: View {
    let entries: [(name: String, address: String, systemImage: String)]

    @State private var pins: [TripMapPin] = []
    @State private var position: MapCameraPosition = .automatic
    @State private var didGeocode = false

    var body: some View {
        Group {
            if !pins.isEmpty {
                Map(position: $position) {
                    ForEach(pins) { pin in
                        Marker(pin.name, systemImage: pin.systemImage, coordinate: pin.coordinate)
                            .tint(Theme.Colors.brand)
                    }
                }
                .frame(height: 220)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .allowsHitTesting(false)
            }
        }
        .task {
            guard !didGeocode else { return }
            didGeocode = true
            await geocodeAll()
        }
    }

    private func geocodeAll() async {
        let geocoder = CLGeocoder()
        var result: [TripMapPin] = []
        // Sequential — CLGeocoder throttles concurrent requests.
        for entry in entries where !entry.address.isEmpty {
            if let placemarks = try? await geocoder.geocodeAddressString(entry.address),
               let loc = placemarks.first?.location {
                result.append(TripMapPin(name: entry.name,
                                         coordinate: loc.coordinate,
                                         systemImage: entry.systemImage))
            }
        }
        pins = result
        if let first = result.first {
            position = .region(MKCoordinateRegion(center: first.coordinate,
                                                  latitudinalMeters: 40000,
                                                  longitudinalMeters: 40000))
        }
    }
}
