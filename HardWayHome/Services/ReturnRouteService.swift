import Foundation
import MapKit
import os

private let log = Logger(subsystem: "com.gwynmorfey.hardwayhome.native", category: "returnroute")

/// Estimated distance from the current position back to the workout start point.
struct ReturnEstimate: Equatable, Sendable {
    var metres: Double
    /// True when this is a straight-line estimate (routing unavailable or pending),
    /// false when it came from a walking route.
    var isCrowFlies: Bool
}

/// Abstracts the routing backend so tests can stub it.
protocol WalkingRouter: Sendable {
    func walkingDistanceMetres(fromLat: Double, fromLng: Double,
                               toLat: Double, toLng: Double) async throws -> Double
}

/// Routes via MapKit's directions service with walking rules.
struct MapKitWalkingRouter: WalkingRouter {
    func walkingDistanceMetres(fromLat: Double, fromLng: Double,
                               toLat: Double, toLng: Double) async throws -> Double {
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(
            coordinate: CLLocationCoordinate2D(latitude: fromLat, longitude: fromLng)))
        request.destination = MKMapItem(placemark: MKPlacemark(
            coordinate: CLLocationCoordinate2D(latitude: toLat, longitude: toLng)))
        request.transportType = .walking
        request.requestsAlternateRoutes = false
        let response = try await MKDirections(request: request).calculate()
        guard let route = response.routes.first else {
            throw MKError(.directionsNotFound)
        }
        return route.distance
    }
}

/// Maintains a live estimate of the distance home. Shows crow-flies immediately,
/// and replaces it with a routed walking distance fetched at most once per
/// `refreshSeconds` — and only after `minMovementMetres` of movement since the
/// last successful fetch, so a paused runner doesn't burn requests.
@MainActor
@Observable
final class ReturnRouteService {

    static let refreshSeconds: Double = 60
    static let throttleBackoffSeconds: Double = 180
    static let minMovementMetres: Double = 200

    private(set) var estimate: ReturnEstimate? = nil

    /// Injectable for tests; production routes via MapKit.
    var router: any WalkingRouter = MapKitWalkingRouter()

    private var inFlight = false
    private var nextAttemptAt: TimeInterval = 0
    /// Where the last successful fetch was made from; nil after a failure so the
    /// retry is gated on time alone (a stationary runner would otherwise never
    /// recover the routed number).
    private var lastSuccessOrigin: (lat: Double, lng: Double)?
    /// Invalidates in-flight fetches from a previous workout after `reset()`.
    private var generation = 0

    /// Clear all state for a new workout.
    func reset() {
        generation += 1
        estimate = nil
        inFlight = false
        nextAttemptAt = 0
        lastSuccessOrigin = nil
    }

    /// Report the latest position. Updates the crow-flies estimate synchronously
    /// and starts a routed fetch when the refresh gates allow. Returns the fetch
    /// task if one was started (tests await it; production ignores it).
    @discardableResult
    func noteLocation(startLat: Double, startLng: Double,
                      currentLat: Double, currentLng: Double,
                      now: TimeInterval) -> Task<Void, Never>? {
        if estimate == nil || estimate?.isCrowFlies == true {
            estimate = ReturnEstimate(
                metres: Geo.haversineMetres(currentLat, currentLng, startLat, startLng),
                isCrowFlies: true)
        }

        guard !inFlight, now >= nextAttemptAt else { return nil }
        if let origin = lastSuccessOrigin,
           Geo.haversineMetres(origin.lat, origin.lng, currentLat, currentLng)
               < Self.minMovementMetres {
            return nil
        }

        inFlight = true
        nextAttemptAt = now + Self.refreshSeconds
        let gen = generation
        return Task {
            await fetchRoute(startLat: startLat, startLng: startLng,
                             currentLat: currentLat, currentLng: currentLng,
                             now: now, gen: gen)
        }
    }

    private func fetchRoute(startLat: Double, startLng: Double,
                            currentLat: Double, currentLng: Double,
                            now: TimeInterval, gen: Int) async {
        defer { if gen == generation { inFlight = false } }
        do {
            let metres = try await router.walkingDistanceMetres(
                fromLat: currentLat, fromLng: currentLng,
                toLat: startLat, toLng: startLng)
            guard gen == generation else { return }
            estimate = ReturnEstimate(metres: metres, isCrowFlies: false)
            lastSuccessOrigin = (currentLat, currentLng)
        } catch {
            guard gen == generation else { return }
            lastSuccessOrigin = nil
            estimate = ReturnEstimate(
                metres: Geo.haversineMetres(currentLat, currentLng, startLat, startLng),
                isCrowFlies: true)
            if (error as? MKError)?.code == .loadingThrottled {
                nextAttemptAt = now + Self.throttleBackoffSeconds
            }
            log.warning("Return route fetch failed: \(error)")
        }
    }
}
