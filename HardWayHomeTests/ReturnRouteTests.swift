import Testing
import Foundation
import MapKit
@testable import HardWayHome

/// Thread-safe stub router. Shared by any test that pumps trackpoints through
/// WorkoutStatsVM, so unit tests never hit Apple's directions service.
final class StubRouter: WalkingRouter, @unchecked Sendable {
    private let lock = NSLock()
    private var _result: Result<Double, Error>
    private var _calls = 0

    init(_ result: Result<Double, Error>) { _result = result }

    var calls: Int { lock.withLock { _calls } }
    func set(_ result: Result<Double, Error>) { lock.withLock { _result = result } }

    func walkingDistanceMetres(fromLat: Double, fromLng: Double,
                               toLat: Double, toLng: Double) async throws -> Double {
        lock.withLock { _calls += 1 }
        return try lock.withLock { _result }.get()
    }
}

@Suite("Return route")
struct ReturnRouteTests {

    // 0.001° of latitude ≈ 111 m. Start is fixed; "current" varies per test.
    private let start = (lat: 51.5, lng: -0.1)

    @MainActor
    private func note(_ svc: ReturnRouteService, currentLat: Double,
                      now: TimeInterval) -> Task<Void, Never>? {
        svc.noteLocation(startLat: start.lat, startLng: start.lng,
                         currentLat: currentLat, currentLng: start.lng, now: now)
    }

    @Test("Crow-flies shows immediately, routed distance replaces it")
    @MainActor
    func routedReplacesCrowFlies() async {
        let svc = ReturnRouteService()
        svc.router = StubRouter(.success(1500))
        let t0 = epoch("2026-08-08T10:00:00Z")

        let task = note(svc, currentLat: 51.51, now: t0)
        #expect(svc.estimate?.isCrowFlies == true)
        #expect(abs((svc.estimate?.metres ?? 0) - 1112) < 5)

        await task?.value
        #expect(svc.estimate == ReturnEstimate(metres: 1500, isCrowFlies: false))
    }

    @Test("Refetch is gated on 60s elapsed AND 200m moved")
    @MainActor
    func refreshGating() async {
        let svc = ReturnRouteService()
        let router = StubRouter(.success(1500))
        svc.router = router
        let t0 = epoch("2026-08-08T10:00:00Z")

        await note(svc, currentLat: 51.51, now: t0)?.value
        #expect(router.calls == 1)

        // Moved plenty but within 60s: no refetch.
        #expect(note(svc, currentLat: 51.515, now: t0 + 30) == nil)

        // 60s elapsed but only ~167m from the last fetch origin: no refetch.
        #expect(note(svc, currentLat: 51.5115, now: t0 + 61) == nil)

        // The routed estimate survives the gated calls.
        #expect(svc.estimate?.isCrowFlies == false)

        // 60s elapsed and ~222m moved: refetch.
        let task = note(svc, currentLat: 51.512, now: t0 + 61)
        #expect(task != nil)
        await task?.value
        #expect(router.calls == 2)
    }

    @Test("Failure falls back to crow-flies and retries on time alone")
    @MainActor
    func failureFallsBack() async {
        let svc = ReturnRouteService()
        let router = StubRouter(.failure(MKError(.serverFailure)))
        svc.router = router
        let t0 = epoch("2026-08-08T10:00:00Z")

        await note(svc, currentLat: 51.51, now: t0)?.value
        #expect(svc.estimate?.isCrowFlies == true)
        #expect(abs((svc.estimate?.metres ?? 0) - 1112) < 5)

        // Stationary since the failed attempt: the movement gate must not block
        // recovery once the connection is back.
        router.set(.success(1500))
        let task = note(svc, currentLat: 51.51, now: t0 + 61)
        #expect(task != nil)
        await task?.value
        #expect(svc.estimate == ReturnEstimate(metres: 1500, isCrowFlies: false))
    }

    @Test("Throttling backs off for 180s")
    @MainActor
    func throttleBackoff() async {
        let svc = ReturnRouteService()
        svc.router = StubRouter(.failure(MKError(.loadingThrottled)))
        let t0 = epoch("2026-08-08T10:00:00Z")

        await note(svc, currentLat: 51.51, now: t0)?.value
        #expect(svc.estimate?.isCrowFlies == true)

        #expect(note(svc, currentLat: 51.52, now: t0 + 61) == nil)
        #expect(note(svc, currentLat: 51.52, now: t0 + 181) != nil)
    }

    @Test("reset() discards an in-flight fetch from the previous workout")
    @MainActor
    func resetDiscardsInFlight() async {
        let svc = ReturnRouteService()
        svc.router = StubRouter(.success(1500))
        let t0 = epoch("2026-08-08T10:00:00Z")

        // The fetch task is created but hasn't run yet (we haven't suspended).
        let task = note(svc, currentLat: 51.51, now: t0)
        svc.reset()
        await task?.value
        #expect(svc.estimate == nil)
    }

    @Test("VM exposes return distance and ETA from the current 1km pace")
    @MainActor
    func vmReturnEta() throws {
        let db = try AppDatabase.empty()
        let vm = WorkoutStatsVM(db: db)
        vm.returnRoute.router = StubRouter(.failure(MKError(.serverFailure)))

        let base = epoch("2026-06-28T10:00:00Z")
        vm.observe(workoutId: 1, startedAt: base,
                   locationService: LocationService(db: db),
                   heartRateService: HeartRateService(db: db))

        // 10 points in a straight line, ~111 m and 30 s apart.
        for i in 0..<10 {
            vm.onTrackpoint(Trackpoint(workoutId: 1, createdAt: base + Double(i * 30),
                                       lat: 51.5 + Double(i) * 0.001, lng: -0.1,
                                       speed: nil, err: 5))
        }

        // No routed fetch has resolved, so this is the crow-flies estimate:
        // ~1001 m at ~270 s/km pace → ETA ~270 s.
        #expect(vm.returnIsCrowFlies == true)
        let distance = try #require(vm.returnDistance)
        #expect(abs(distance - 1001) < 5)
        let eta = try #require(vm.returnEtaSeconds)
        #expect(abs(eta - 270) < 5)

        vm.stop()
    }
}
