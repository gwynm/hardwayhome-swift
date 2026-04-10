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

    // MARK: - Checkpoint tests

    private func makeSplits(_ times: [Double]) -> [KmSplit] {
        times.enumerated().map { KmSplit(km: $0.offset + 1, seconds: $0.element, avgBpm: nil) }
    }

    @Test("Checkpoint: 5 consecutive splits at same pace")
    func checkpointBasic() {
        // 5 splits all at exactly 5:30 (330s)
        let splits = makeSplits([330, 330, 330, 330, 330])
        let cp = SplitCalc.computeCheckpoint(splits: splits)
        #expect(cp != nil)
        #expect(cp?.count == 5)
        #expect(cp?.paceSec == 330)
    }

    @Test("Checkpoint: fewer than 5 splits returns nil")
    func checkpointTooFew() {
        let splits = makeSplits([300, 300, 300, 300])
        #expect(SplitCalc.computeCheckpoint(splits: splits) == nil)
    }

    @Test("Checkpoint: faster beats longer")
    func checkpointFasterBeatsLonger() {
        // 6 splits at 5:45 (345s) and 5 at 5:30 (330s) — the 5 x 5:30 should win
        let splits = makeSplits([345, 345, 345, 345, 345, 345, 320, 325, 328, 329, 330])
        let cp = SplitCalc.computeCheckpoint(splits: splits)
        #expect(cp != nil)
        #expect(cp?.paceSec == 330)
        #expect(cp?.count == 5)
    }

    @Test("Checkpoint: all splits slower than 7:00 returns nil")
    func checkpointTooSlow() {
        let splits = makeSplits([430, 430, 430, 430, 430])
        #expect(SplitCalc.computeCheckpoint(splits: splits) == nil)
    }

    @Test("Checkpoint: pace rounds up to multiple of 15")
    func checkpointPaceRounding() {
        // 5 splits at 301s — rounds up to 315 (5:15)
        let splits = makeSplits([301, 301, 301, 301, 301])
        let cp = SplitCalc.computeCheckpoint(splits: splits)
        #expect(cp?.paceSec == 315)
    }

    @Test("Checkpoint: picks longest run at a given pace")
    func checkpointLongestRun() {
        // 7 consecutive at 6:00 (360s)
        let splits = makeSplits([360, 360, 360, 360, 360, 360, 360])
        let cp = SplitCalc.computeCheckpoint(splits: splits)
        #expect(cp?.count == 7)
        #expect(cp?.paceSec == 360)
    }

    @Test("Checkpoint: gap breaks consecutive run")
    func checkpointGapBreaks() {
        // 3 fast, 1 slow, 3 fast — no 5 consecutive at the fast pace
        let splits = makeSplits([300, 300, 300, 500, 300, 300, 300])
        // At 420 (7:00): [300, 300, 300, X, 300, 300, 300] — longest run is 3, not enough
        // 500 > 420, so no checkpoint at any pace
        #expect(SplitCalc.computeCheckpoint(splits: splits) == nil)
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
