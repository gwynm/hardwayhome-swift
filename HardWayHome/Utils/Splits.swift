import Foundation

/// Km split computation.
enum SplitCalc {

    /// Compute per-kilometre splits from trackpoints and pulse data.
    ///
    /// Walks through trackpoints accumulating distance. Each time the accumulated
    /// distance crosses a 1 km boundary, a split is recorded with the elapsed time
    /// and the average BPM of pulses that fall within that time window.
    ///
    /// Only completed kilometres are included — the final partial km is omitted.
    static func computeKmSplits(trackpoints: [Trackpoint], pulses: [Pulse]) -> [KmSplit] {
        guard trackpoints.count >= 2 else { return [] }

        var splits: [KmSplit] = []
        var cumulativeDistance = 0.0
        var splitStartTime = Formatting.parseISO(trackpoints[0].createdAt) ?? Date.distantPast
        var nextKmBoundary = 1000.0
        var pulseIdx = 0

        for i in 1..<trackpoints.count {
            let segDist = Geo.haversineMetres(
                trackpoints[i - 1].lat, trackpoints[i - 1].lng,
                trackpoints[i].lat, trackpoints[i].lng)
            cumulativeDistance += segDist

            if cumulativeDistance >= nextKmBoundary {
                let splitEndTime = Formatting.parseISO(trackpoints[i].createdAt) ?? Date.distantPast
                let seconds = splitEndTime.timeIntervalSince(splitStartTime)

                let startMs = splitStartTime.timeIntervalSince1970
                let endMs = splitEndTime.timeIntervalSince1970

                let avgBpm = averageBpmInWindow(
                    pulses: pulses, startIdx: pulseIdx,
                    startSec: startMs, endSec: endMs)
                pulseIdx = advancePulseIdx(pulses: pulses, currentIdx: pulseIdx, endSec: endMs)

                splits.append(KmSplit(km: splits.count + 1, seconds: seconds, avgBpm: avgBpm))

                splitStartTime = splitEndTime
                nextKmBoundary += 1000
            }
        }

        return splits
    }

    /// Average BPM of pulses whose created_at falls within [startSec, endSec] (epoch seconds).
    private static func averageBpmInWindow(
        pulses: [Pulse], startIdx: Int, startSec: Double, endSec: Double
    ) -> Double? {
        var sum = 0.0
        var count = 0

        for i in startIdx..<pulses.count {
            guard let t = Formatting.parseISO(pulses[i].createdAt) else { continue }
            let epoch = t.timeIntervalSince1970
            if epoch > endSec { break }
            if epoch >= startSec {
                sum += Double(pulses[i].bpm)
                count += 1
            }
        }

        return count > 0 ? sum / Double(count) : nil
    }

    /// Advance pulse index past all pulses up to endSec.
    private static func advancePulseIdx(
        pulses: [Pulse], currentIdx: Int, endSec: Double
    ) -> Int {
        var idx = currentIdx
        while idx < pulses.count,
              let t = Formatting.parseISO(pulses[idx].createdAt),
              t.timeIntervalSince1970 <= endSec {
            idx += 1
        }
        return idx
    }
}
