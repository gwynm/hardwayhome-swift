import Testing
@testable import HardWayHome

@Suite("Trackpoint Filter")
struct TrackpointFilterTests {

    private func makeTP(lat: Double, lng: Double, err: Double?, createdAt: String) -> Trackpoint {
        Trackpoint(workoutId: 1, createdAt: createdAt, lat: lat, lng: lng, speed: nil, err: err)
    }

    @Test("Filters out nil accuracy")
    func nilAccuracy() {
        let tps = [
            makeTP(lat: 51.5, lng: -0.1, err: nil, createdAt: "2026-02-13T11:30:00Z"),
            makeTP(lat: 51.5, lng: -0.1, err: 10, createdAt: "2026-02-13T11:30:10Z"),
        ]
        let filtered = TrackpointFilter.filterReliable(tps)
        #expect(filtered.count == 1)
    }

    @Test("Filters out high accuracy error")
    func highError() {
        let tps = [
            makeTP(lat: 51.5, lng: -0.1, err: 25, createdAt: "2026-02-13T11:30:00Z"),
            makeTP(lat: 51.5, lng: -0.1, err: 5, createdAt: "2026-02-13T11:30:10Z"),
            makeTP(lat: 51.5, lng: -0.1, err: 19.9, createdAt: "2026-02-13T11:30:20Z"),
        ]
        let filtered = TrackpointFilter.filterReliable(tps)
        #expect(filtered.count == 2)
    }

    @Test("Filters out speed teleports")
    func speedFilter() {
        // Two points ~11km apart in 10s = 1100 m/s — way above 14 m/s threshold
        let tps = [
            makeTP(lat: 51.5, lng: -0.1, err: 5, createdAt: "2026-02-13T11:30:00Z"),
            makeTP(lat: 51.6, lng: -0.1, err: 5, createdAt: "2026-02-13T11:30:10Z"),
        ]
        let filtered = TrackpointFilter.filterReliable(tps)
        #expect(filtered.count == 1)  // second point rejected
    }

    @Test("Keeps normal-speed points")
    func normalSpeed() {
        // ~10m apart in 10s = 1 m/s — well under threshold
        let tps = [
            makeTP(lat: 51.50000, lng: -0.10000, err: 5, createdAt: "2026-02-13T11:30:00Z"),
            makeTP(lat: 51.50009, lng: -0.10000, err: 5, createdAt: "2026-02-13T11:30:10Z"),
        ]
        let filtered = TrackpointFilter.filterReliable(tps)
        #expect(filtered.count == 2)
    }

    @Test("Empty input returns empty")
    func emptyInput() {
        #expect(TrackpointFilter.filterReliable([]).isEmpty)
    }
}
