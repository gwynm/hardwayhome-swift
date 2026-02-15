import Testing
import Foundation
@testable import HardWayHome

@Suite("Pace Calculations")
struct PaceTests {

    private func makeTP(lat: Double, lng: Double, createdAt: TimeInterval) -> Trackpoint {
        Trackpoint(workoutId: 1, createdAt: createdAt, lat: lat, lng: lng, speed: nil, err: 5)
    }

    @Test("paceOverWindow with insufficient points")
    func insufficientPoints() {
        let base = epoch("2026-02-13T11:30:00Z")
        let tp = makeTP(lat: 51.5, lng: -0.1, createdAt: base)
        #expect(PaceCalc.paceOverWindow([tp], windowMetres: 100) == nil)
        #expect(PaceCalc.paceOverWindow([], windowMetres: 100) == nil)
    }

    @Test("paceOverWindow with insufficient distance")
    func insufficientDistance() {
        let base = epoch("2026-02-13T11:30:00Z")
        let tps = [
            makeTP(lat: 51.50000, lng: -0.10000, createdAt: base),
            makeTP(lat: 51.50009, lng: -0.10000, createdAt: base + 10),
        ]
        #expect(PaceCalc.paceOverWindow(tps, windowMetres: 100) == nil)
    }

    @Test("paceOverWindow returns reasonable value")
    func reasonablePace() {
        let base = epoch("2026-02-13T11:30:00Z")
        var tps: [Trackpoint] = []
        for i in 0..<20 {
            let lat = 51.5000 + Double(i) * 0.001
            tps.append(makeTP(lat: lat, lng: -0.1, createdAt: base + Double(i * 30)))
        }
        let pace = PaceCalc.paceOverWindow(tps, windowMetres: 100)
        if let p = pace {
            #expect(p > 100 && p < 1000)
        }
    }

    @Test("trackpointDistance")
    func trackpointDistanceTest() {
        let base = epoch("2026-02-13T11:30:00Z")
        let tps = [
            makeTP(lat: 51.500, lng: -0.100, createdAt: base),
            makeTP(lat: 51.501, lng: -0.100, createdAt: base + 10),
        ]
        let d = PaceCalc.trackpointDistance(tps)
        #expect(d > 100 && d < 120)
    }
}
