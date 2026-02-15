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
}
