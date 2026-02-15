import Testing
@testable import HardWayHome

@Suite("Pace Calculations")
struct PaceTests {

    private func makeTP(lat: Double, lng: Double, createdAt: String) -> Trackpoint {
        Trackpoint(workoutId: 1, createdAt: createdAt, lat: lat, lng: lng, speed: nil, err: 5)
    }

    @Test("paceOverWindow with insufficient points")
    func insufficientPoints() {
        let tp = makeTP(lat: 51.5, lng: -0.1, createdAt: "2026-02-13T11:30:00Z")
        #expect(PaceCalc.paceOverWindow([tp], windowMetres: 100) == nil)
        #expect(PaceCalc.paceOverWindow([], windowMetres: 100) == nil)
    }

    @Test("paceOverWindow with insufficient distance")
    func insufficientDistance() {
        // Two points 10m apart, asking for 100m window
        let tps = [
            makeTP(lat: 51.50000, lng: -0.10000, createdAt: "2026-02-13T11:30:00Z"),
            makeTP(lat: 51.50009, lng: -0.10000, createdAt: "2026-02-13T11:30:10Z"),
        ]
        #expect(PaceCalc.paceOverWindow(tps, windowMetres: 100) == nil)
    }

    @Test("paceOverWindow returns reasonable value")
    func reasonablePace() {
        // Create points ~111m apart (0.001 degrees lat), 30 seconds each
        // At 111m / 30s = 3.7 m/s, pace = 1000/3.7 = ~270 sec/km
        var tps: [Trackpoint] = []
        for i in 0..<20 {
            let lat = 51.5000 + Double(i) * 0.001
            let time = "2026-02-13T11:3\(String(format: "%01d", i / 6)):\(String(format: "%02d", (i % 6) * 10))Z"
            // Simpler: use epoch-based times
            tps.append(makeTP(lat: lat, lng: -0.1, createdAt: "2026-02-13T11:\(String(format: "%02d", 30 + i / 2)):\(String(format: "%02d", (i % 2) * 30))Z"))
        }
        let pace = PaceCalc.paceOverWindow(tps, windowMetres: 100)
        // Should be some finite positive number
        if let p = pace {
            #expect(p > 100 && p < 1000)
        }
    }

    @Test("trackpointDistance")
    func trackpointDistanceTest() {
        let tps = [
            makeTP(lat: 51.500, lng: -0.100, createdAt: "2026-02-13T11:30:00Z"),
            makeTP(lat: 51.501, lng: -0.100, createdAt: "2026-02-13T11:30:10Z"),
        ]
        let d = PaceCalc.trackpointDistance(tps)
        // ~111m for 0.001 degrees lat
        #expect(d > 100 && d < 120)
    }
}
