import Foundation

/// Km split computation.
enum SplitCalc {

    /// Compute per-kilometre splits from trackpoints and pulse data.
    static func computeKmSplits(trackpoints: [Trackpoint], pulses: [Pulse]) -> [KmSplit] {
        guard trackpoints.count >= 2 else { return [] }

        var splits: [KmSplit] = []
        var cumulativeDistance = 0.0
        var splitStartEpoch = trackpoints[0].createdAt
        var nextKmBoundary = 1000.0
        var pulseIdx = 0

        for i in 1..<trackpoints.count {
            let segDist = Geo.haversineMetres(
                trackpoints[i - 1].lat, trackpoints[i - 1].lng,
                trackpoints[i].lat, trackpoints[i].lng)
            cumulativeDistance += segDist

            if cumulativeDistance >= nextKmBoundary {
                let splitEndEpoch = trackpoints[i].createdAt
                let seconds = splitEndEpoch - splitStartEpoch

                let avgBpm = averageBpmInWindow(
                    pulses: pulses, startIdx: pulseIdx,
                    startSec: splitStartEpoch, endSec: splitEndEpoch)
                pulseIdx = advancePulseIdx(
                    pulses: pulses, currentIdx: pulseIdx, endSec: splitEndEpoch)

                splits.append(KmSplit(km: splits.count + 1, seconds: seconds, avgBpm: avgBpm))

                splitStartEpoch = splitEndEpoch
                nextKmBoundary += 1000
            }
        }

        return splits
    }

    private static func averageBpmInWindow(
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

    private static func advancePulseIdx(
        pulses: [Pulse], currentIdx: Int, endSec: Double
    ) -> Int {
        var idx = currentIdx
        while idx < pulses.count, pulses[idx].createdAt <= endSec {
            idx += 1
        }
        return idx
    }
}
