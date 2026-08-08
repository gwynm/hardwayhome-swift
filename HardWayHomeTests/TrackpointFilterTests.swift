import Testing
import Foundation
@testable import HardWayHome

@Suite("Trackpoint Filter")
struct TrackpointFilterTests {

    private func makeTP(lat: Double, lng: Double, err: Double?, createdAt: TimeInterval) -> Trackpoint {
        Trackpoint(workoutId: 1, createdAt: createdAt, lat: lat, lng: lng, speed: nil, err: err)
    }

    @Test("Filters out nil accuracy")
    func nilAccuracy() {
        let base = epoch("2026-02-13T11:30:00Z")
        let tps = [
            makeTP(lat: 51.5, lng: -0.1, err: nil, createdAt: base),
            makeTP(lat: 51.5, lng: -0.1, err: 10, createdAt: base + 10),
        ]
        let filtered = TrackpointFilter.filterReliable(tps)
        #expect(filtered.count == 1)
    }

    @Test("Filters out high accuracy error")
    func highError() {
        let base = epoch("2026-02-13T11:30:00Z")
        let tps = [
            makeTP(lat: 51.5, lng: -0.1, err: 25, createdAt: base),
            makeTP(lat: 51.5, lng: -0.1, err: 5, createdAt: base + 10),
            makeTP(lat: 51.5, lng: -0.1, err: 19.9, createdAt: base + 20),
        ]
        let filtered = TrackpointFilter.filterReliable(tps)
        #expect(filtered.count == 2)
    }

    @Test("Filters out speed teleports")
    func speedFilter() {
        let base = epoch("2026-02-13T11:30:00Z")
        let tps = [
            makeTP(lat: 51.5, lng: -0.1, err: 5, createdAt: base),
            makeTP(lat: 51.6, lng: -0.1, err: 5, createdAt: base + 10),
        ]
        let filtered = TrackpointFilter.filterReliable(tps)
        #expect(filtered.count == 1)
    }

    @Test("Keeps normal-speed points")
    func normalSpeed() {
        let base = epoch("2026-02-13T11:30:00Z")
        let tps = [
            makeTP(lat: 51.50000, lng: -0.10000, err: 5, createdAt: base),
            makeTP(lat: 51.50009, lng: -0.10000, err: 5, createdAt: base + 10),
        ]
        let filtered = TrackpointFilter.filterReliable(tps)
        #expect(filtered.count == 2)
    }

    @Test("Empty input returns empty")
    func emptyInput() {
        #expect(TrackpointFilter.filterReliable([]).isEmpty)
    }

    // MARK: - GPS-drift removal

    /// Metres-per-degree is ~111_320 at the equator; good enough for small offsets.
    private let mPerDegLat = 111_320.0

    /// Build a straight walk heading north at ~1.4 m/s with a good fix.
    private func straightWalk(count: Int, from base: TimeInterval, startLat: Double = 51.5)
        -> [Trackpoint]
    {
        (0..<count).map { i in
            makeTP(lat: startLat + Double(i) * 5.0 / mPerDegLat, lng: -0.1,
                   err: 5, createdAt: base + Double(i) * 4)
        }
    }

    /// Build a cluster that scribbles around a point (stationary indoors, poor fix):
    /// each point jumps several metres in an alternating direction, so net≈0 but path is large.
    private func driftCluster(count: Int, from base: TimeInterval, at lat: Double, lng: Double)
        -> [Trackpoint]
    {
        (0..<count).map { i in
            let jitterLat = (i % 2 == 0 ? 8.0 : -8.0) / mPerDegLat
            let jitterLng = (i % 3 == 0 ? 7.0 : -6.0) / mPerDegLat
            return makeTP(lat: lat + jitterLat, lng: lng + jitterLng,
                          err: 14, createdAt: base + Double(i) * 3)
        }
    }

    @Test("Removes leading GPS-warmup drift, keeps the real walk")
    func leadingDrift() {
        let base = epoch("2026-02-13T11:30:00Z")
        let drift = driftCluster(count: 12, from: base, at: 51.5, lng: -0.1)
        let walk = straightWalk(count: 12, from: base + 40)
        let filtered = TrackpointFilter.filterReliable(drift + walk)
        // The straight walk survives; the scribble is gone.
        #expect(filtered.count >= 10)
        #expect(filtered.count <= walk.count + 1)
    }

    @Test("Removes mid-walk drift (e.g. stepping into a building)")
    func midWalkDrift() {
        let base = epoch("2026-02-13T11:30:00Z")
        let before = straightWalk(count: 12, from: base)
        let lastBefore = before.last!
        let drift = driftCluster(count: 12, from: lastBefore.createdAt + 4,
                                 at: lastBefore.lat, lng: lastBefore.lng)
        let after = straightWalk(count: 12, from: drift.last!.createdAt + 4,
                                 startLat: lastBefore.lat)
        let filtered = TrackpointFilter.filterReliable(before + drift + after)
        let distance = PaceCalc.trackpointDistance(filtered)
        // ~23 straight steps of 5 m ≈ 115 m; the drift must not inflate it past a small margin.
        #expect(distance < 160)
    }

    @Test("Keeps a clean straight walk intact")
    func cleanWalkUntouched() {
        let base = epoch("2026-02-13T11:30:00Z")
        let walk = straightWalk(count: 20, from: base)
        #expect(TrackpointFilter.filterReliable(walk).count == 20)
    }

    @Test("Keeps a genuine out-and-back (low net displacement, but locally straight)")
    func outAndBackKept() {
        let base = epoch("2026-02-13T11:30:00Z")
        let out = straightWalk(count: 12, from: base)
        let turn = out.last!
        // Walk back south on the other side of the path (~6 m offset) — net displacement ≈ 0
        // overall, but every step is locally coherent, like a real out-and-back route.
        let backLng = -0.1 + 6.0 / (mPerDegLat * cos(51.5 * .pi / 180))
        let back = (1...12).map { i in
            makeTP(lat: turn.lat - Double(i) * 5.0 / mPerDegLat, lng: backLng,
                   err: 5, createdAt: turn.createdAt + Double(i) * 4)
        }
        let filtered = TrackpointFilter.filterReliable(out + back)
        // A few points around the sharp apex may be trimmed, but — unlike drift — the
        // real out-and-back distance (~115 m) is preserved, not collapsed.
        #expect(PaceCalc.trackpointDistance(filtered) > 95)
    }

    @Test("Does not flag a standstill with a good fix (tiny jitter, no phantom distance)")
    func standstillKept() {
        let base = epoch("2026-02-13T11:30:00Z")
        // 10 points jittering within ~1 m — net≈0 but path is also tiny, so not drift.
        let still = (0..<10).map { i in
            makeTP(lat: 51.5 + (i % 2 == 0 ? 0.5 : -0.5) / mPerDegLat,
                   lng: -0.1, err: 5, createdAt: base + Double(i) * 3)
        }
        #expect(TrackpointFilter.withoutDrift(still).count == still.count)
    }
}
