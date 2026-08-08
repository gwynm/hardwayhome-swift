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

    @Test("Checkpoint: a single split returns nil")
    func checkpointTooFew() {
        let splits = makeSplits([300])
        #expect(SplitCalc.computeCheckpoint(splits: splits) == nil)
    }

    @Test("Checkpoint: 2 consecutive splits is the minimum")
    func checkpointMinimumTwo() {
        let splits = makeSplits([420, 420])
        let cp = SplitCalc.computeCheckpoint(splits: splits)
        #expect(cp?.count == 2)
        #expect(cp?.paceSec == 420)
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

    @Test("Checkpoint: all splits slower than 8:00 returns nil")
    func checkpointTooSlow() {
        let splits = makeSplits([490, 490, 490, 490, 490])
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
        // 3 fast, 1 slow, 3 fast — the 500s split (> 8:00) breaks the run,
        // leaving two runs of 3 at 5:00
        let splits = makeSplits([300, 300, 300, 500, 300, 300, 300])
        let cp = SplitCalc.computeCheckpoint(splits: splits)
        #expect(cp?.count == 3)
        #expect(cp?.paceSec == 300)
    }

    @Test("Checkpoint: exactly 5 splits at 8:00 boundary")
    func checkpointAtMaxPace() {
        let splits = makeSplits([480, 480, 480, 480, 480])
        let cp = SplitCalc.computeCheckpoint(splits: splits)
        #expect(cp != nil)
        #expect(cp?.count == 5)
        #expect(cp?.paceSec == 480)
    }

    @Test("Checkpoint: mixed paces, slow one in middle still allows slower checkpoint")
    func checkpointSlowMiddle() {
        // 5 at 5:00, 1 at 6:00, 5 at 5:00
        // At pace 300: runs of 5 and 5 — checkpoint is 5 x 5:00
        // At pace 360: run of 11 — checkpoint would be 11 x 6:00
        // Faster wins: 5 x 5:00
        let splits = makeSplits([300, 300, 300, 300, 300, 360, 300, 300, 300, 300, 300])
        let cp = SplitCalc.computeCheckpoint(splits: splits)
        #expect(cp?.paceSec == 300)
        #expect(cp?.count == 5)
    }

    @Test("Checkpoint: prefers longer run at the same pace")
    func checkpointLongerAtSamePace() {
        // 8 consecutive at exactly 5:00 (300s)
        let splits = makeSplits([300, 300, 300, 300, 300, 300, 300, 300])
        let cp = SplitCalc.computeCheckpoint(splits: splits)
        #expect(cp?.count == 8)
        #expect(cp?.paceSec == 300)
    }

    @Test("Checkpoint: splits just over threshold don't count")
    func checkpointJustOver() {
        // 5 splits at 315.1s — rounds up to 330, but only 315 threshold checked first
        // At 315: none qualify. At 330: all qualify → 5 x 5:30
        let splits = makeSplits([315.1, 315.1, 315.1, 315.1, 315.1])
        let cp = SplitCalc.computeCheckpoint(splits: splits)
        #expect(cp?.paceSec == 330)
        #expect(cp?.count == 5)
    }

    @Test("Checkpoint: exactly on 15s boundary counts at that boundary")
    func checkpointExactBoundary() {
        let splits = makeSplits([315, 315, 315, 315, 315])
        let cp = SplitCalc.computeCheckpoint(splits: splits)
        #expect(cp?.paceSec == 315)
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
