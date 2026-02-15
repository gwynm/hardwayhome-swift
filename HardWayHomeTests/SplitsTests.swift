import Testing
@testable import HardWayHome

@Suite("Km Splits")
struct SplitsTests {

    @Test("No splits from too few trackpoints")
    func tooFew() {
        let splits = SplitCalc.computeKmSplits(trackpoints: [], pulses: [])
        #expect(splits.isEmpty)
    }

    @Test("No splits when distance < 1km")
    func underOneKm() {
        let base = epoch("2026-02-13T11:30:00Z")
        let tps = [
            Trackpoint(workoutId: 1, createdAt: base,
                       lat: 51.500, lng: -0.100, speed: nil, err: 5),
            Trackpoint(workoutId: 1, createdAt: base + 30,
                       lat: 51.501, lng: -0.100, speed: nil, err: 5),
        ]
        let splits = SplitCalc.computeKmSplits(trackpoints: tps, pulses: [])
        #expect(splits.isEmpty)
    }

    @Test("One split for >1km route")
    func oneSplit() {
        let base = epoch("2026-02-13T11:30:00Z")
        var tps: [Trackpoint] = []
        for i in 0..<11 {
            let lat = 51.5000 + Double(i) * 0.001
            tps.append(Trackpoint(
                workoutId: 1, createdAt: base + Double(i * 30),
                lat: lat, lng: -0.100, speed: nil, err: 5))
        }

        let splits = SplitCalc.computeKmSplits(trackpoints: tps, pulses: [])
        #expect(splits.count == 1)
        #expect(splits.first?.km == 1)
        #expect(splits.first?.avgBpm == nil)
    }

    @Test("Splits include average BPM from pulses")
    func splitsWithBpm() {
        let base = epoch("2026-02-13T11:30:00Z")
        var tps: [Trackpoint] = []
        var pulses: [Pulse] = []
        for i in 0..<11 {
            let lat = 51.5000 + Double(i) * 0.001
            let t = base + Double(i * 30)
            tps.append(Trackpoint(
                workoutId: 1, createdAt: t,
                lat: lat, lng: -0.100, speed: nil, err: 5))
            pulses.append(Pulse(workoutId: 1, createdAt: t, bpm: 140 + i))
        }

        let splits = SplitCalc.computeKmSplits(trackpoints: tps, pulses: pulses)
        #expect(splits.count == 1)
        #expect(splits.first?.avgBpm != nil)
    }
}
