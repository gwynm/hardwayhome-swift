import Foundation

/// Km split computation.
enum SplitCalc {

    /// Compute per-kilometre splits from trackpoints and pulse data.
    static func computeKmSplits(trackpoints: [Trackpoint], pulses: [Pulse]) -> [KmSplit] {
        guard trackpoints.count >= 2 else { return [] }

        var state = SplitState()
        for tp in trackpoints {
            state.advance(newTrackpoint: tp, pulses: pulses)
        }
        return state.splits
    }

    // MARK: - Incremental split state

    /// Maintains cursor state for incremental km-split computation.
    /// Feed reliable trackpoints one at a time via `advance(newTrackpoint:pulses:)`.
    struct SplitState {
        var splits: [KmSplit] = []
        private(set) var cumulativeDistance: Double = 0
        private var splitStartEpoch: Double = 0
        private var nextKmBoundary: Double = 1000
        private var pulseIdx: Int = 0
        private var lastTrackpoint: Trackpoint? = nil

        /// Process a new reliable trackpoint, emitting a split if a km boundary is crossed.
        mutating func advance(newTrackpoint tp: Trackpoint, pulses: [Pulse]) {
            guard let prev = lastTrackpoint else {
                lastTrackpoint = tp
                splitStartEpoch = tp.createdAt
                return
            }

            let segDist = Geo.haversineMetres(prev.lat, prev.lng, tp.lat, tp.lng)
            cumulativeDistance += segDist
            lastTrackpoint = tp

            if cumulativeDistance >= nextKmBoundary {
                let seconds = tp.createdAt - splitStartEpoch

                let avgBpm = averageBpmInWindow(
                    pulses: pulses, startIdx: pulseIdx,
                    startSec: splitStartEpoch, endSec: tp.createdAt)
                pulseIdx = advancePulseIdx(
                    pulses: pulses, currentIdx: pulseIdx, endSec: tp.createdAt)

                splits.append(KmSplit(km: splits.count + 1, seconds: seconds, avgBpm: avgBpm))

                splitStartEpoch = tp.createdAt
                nextKmBoundary += 1000
            }
        }
    }

    // MARK: - Checkpoint

    /// Compute the best checkpoint from km splits.
    /// A checkpoint is N consecutive km splits all ≤ some pace (multiple of 15s, ≤ 8:00).
    /// Minimum 2 km. Faster pace beats longer distance; distance breaks ties.
    static func computeCheckpoint(splits: [KmSplit]) -> (count: Int, paceSec: Double)? {
        guard splits.count >= 2 else { return nil }

        let times = splits.map(\.seconds)
        let minTime = times.min()!
        let startPace = max(Int(ceil(minTime / 15.0)) * 15, 15)
        let maxPace = 480 // 8:00

        for pace in stride(from: startPace, through: maxPace, by: 15) {
            let threshold = Double(pace)
            var best = 0
            var current = 0
            for t in times {
                if t <= threshold {
                    current += 1
                    best = max(best, current)
                } else {
                    current = 0
                }
            }
            if best >= 2 {
                return (count: best, paceSec: threshold)
            }
        }
        return nil
    }

    // MARK: - Pulse helpers

    static func averageBpmInWindow(
        pulses: [Pulse], startIdx: Int, startSec: Double, endSec: Double
    ) -> Double? {
        var sum = 0.0
        var count = 0

        for i in startIdx..<pulses.count {
            let epoch = pulses[i].createdAt
            if epoch > endSec { break }
            if epoch >= startSec {
                sum += Double(pulses[i].bpm)
                count += 1
            }
        }

        return count > 0 ? sum / Double(count) : nil
    }

    static func advancePulseIdx(
        pulses: [Pulse], currentIdx: Int, endSec: Double
    ) -> Int {
        var idx = currentIdx
        while idx < pulses.count, pulses[idx].createdAt <= endSec {
            idx += 1
        }
        return idx
    }
}
