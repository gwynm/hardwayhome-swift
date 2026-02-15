import SwiftUI
import MapKit

/// Displays a workout route on an Apple Maps view.
/// When `isLive` is true, shows the user's current position with a heading arrow
/// and keeps the camera centered on the latest position.
struct RouteMapView: View {
    let trackpoints: [Trackpoint]
    var isLive: Bool = false

    var body: some View {
        if trackpoints.count >= 2 {
            let coordinates = trackpoints.map {
                CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lng)
            }

            VStack(alignment: .leading, spacing: 0) {
                Text("Route")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.bottom, 12)

                Map(initialPosition: cameraPosition(for: coordinates)) {
                    MapPolyline(coordinates: coordinates)
                        .stroke(.blue, lineWidth: 3)

                    if isLive {
                        UserAnnotation()
                    }
                }
                .mapStyle(.standard(pointsOfInterest: .excludingAll))
                .mapControls {
                    MapCompass()
                    MapScaleView()
                    if isLive {
                        MapUserLocationButton()
                    }
                }
                .frame(height: 350)
                .clipShape(Rectangle())
            }
            .padding(.top, 24)
            .padding(.horizontal, 16)
        }
    }

    private func cameraPosition(for coords: [CLLocationCoordinate2D]) -> MapCameraPosition {
        guard !coords.isEmpty else { return .automatic }

        if isLive, let last = coords.last {
            // During a live workout, center on the runner's current position
            return .region(MKCoordinateRegion(
                center: last,
                span: MKCoordinateSpan(latitudeDelta: 0.005, longitudeDelta: 0.005)))
        }

        var minLat = Double.infinity, maxLat = -Double.infinity
        var minLng = Double.infinity, maxLng = -Double.infinity

        for c in coords {
            minLat = min(minLat, c.latitude)
            maxLat = max(maxLat, c.latitude)
            minLng = min(minLng, c.longitude)
            maxLng = max(maxLng, c.longitude)
        }

        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2,
            longitude: (minLng + maxLng) / 2)
        let latSpan = (maxLat - minLat) * 1.3
        let lngSpan = (maxLng - minLng) * 1.3
        let span = max(latSpan, lngSpan, 0.002)

        return .region(MKCoordinateRegion(
            center: center,
            span: MKCoordinateSpan(latitudeDelta: span, longitudeDelta: span)))
    }
}
