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
