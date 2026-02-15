import Testing
@testable import HardWayHome

@Suite("Haversine Distance")
struct DistanceTests {

    @Test("Same point returns zero")
    func samePoint() {
        let d = Geo.haversineMetres(51.5, -0.1, 51.5, -0.1)
        #expect(d == 0)
    }

    @Test("Known distance: London to Paris ~340 km")
    func londonToParis() {
        let d = Geo.haversineMetres(51.5074, -0.1278, 48.8566, 2.3522)
        #expect(d > 330_000 && d < 350_000)
    }

    @Test("Short distance: ~100m walk")
    func shortDistance() {
        // ~100m north from a point
        let d = Geo.haversineMetres(51.5000, -0.1000, 51.5009, -0.1000)
        #expect(d > 90 && d < 110)
    }

    @Test("Total distance from points")
    func totalDistance() {
        let points: [(Double, Double)] = [
            (51.500, -0.100),
            (51.501, -0.100),
            (51.002, -0.100),  // big jump
        ]
        let total = Geo.totalDistance(points)
        #expect(total > 55_000)  // Should be large due to the jump
    }

    @Test("Total distance with fewer than 2 points returns zero")
    func totalDistanceSinglePoint() {
        #expect(Geo.totalDistance([]) == 0)
        #expect(Geo.totalDistance([(51.5, -0.1)]) == 0)
    }
}
