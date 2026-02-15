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
        // Two points ~111m apart
        let tps = [
            Trackpoint(workoutId: 1, createdAt: "2026-02-13T11:30:00Z",
                       lat: 51.500, lng: -0.100, speed: nil, err: 5),
            Trackpoint(workoutId: 1, createdAt: "2026-02-13T11:30:30Z",
                       lat: 51.501, lng: -0.100, speed: nil, err: 5),
        ]
        let splits = SplitCalc.computeKmSplits(trackpoints: tps, pulses: [])
        #expect(splits.isEmpty)
    }

    @Test("One split for >1km route")
    func oneSplit() {
        // Create 10 points, each ~111m apart = ~1km total
        // 0.001 degrees lat ≈ 111m
        var tps: [Trackpoint] = []
        for i in 0..<11 {
            let lat = 51.5000 + Double(i) * 0.001
            let seconds = i * 30
            let minute = 30 + seconds / 60
            let sec = seconds % 60
            tps.append(Trackpoint(
                workoutId: 1,
                createdAt: "2026-02-13T11:\(String(format: "%02d", minute)):\(String(format: "%02d", sec))Z",
                lat: lat, lng: -0.100, speed: nil, err: 5))
        }

        let splits = SplitCalc.computeKmSplits(trackpoints: tps, pulses: [])
        #expect(splits.count == 1)
        #expect(splits.first?.km == 1)
        #expect(splits.first?.avgBpm == nil)  // no pulses
    }

    @Test("Splits include average BPM from pulses")
    func splitsWithBpm() {
        var tps: [Trackpoint] = []
        var pulses: [Pulse] = []
        for i in 0..<11 {
            let lat = 51.5000 + Double(i) * 0.001
            let seconds = i * 30
            let minute = 30 + seconds / 60
            let sec = seconds % 60
            let ts = "2026-02-13T11:\(String(format: "%02d", minute)):\(String(format: "%02d", sec))Z"
            tps.append(Trackpoint(
                workoutId: 1, createdAt: ts,
                lat: lat, lng: -0.100, speed: nil, err: 5))
            pulses.append(Pulse(workoutId: 1, createdAt: ts, bpm: 140 + i))
        }

        let splits = SplitCalc.computeKmSplits(trackpoints: tps, pulses: pulses)
        #expect(splits.count == 1)
        #expect(splits.first?.avgBpm != nil)
    }
}
