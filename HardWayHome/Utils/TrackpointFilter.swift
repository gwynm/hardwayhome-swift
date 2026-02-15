import Foundation

/// Trackpoint reliability filtering.
enum TrackpointFilter {
    /// GPS accuracy threshold in metres.
    /// Points with err >= this value (or nil) are excluded.
    static let gpsErrThreshold: Double = 20

    /// Maximum plausible speed in m/s (~50 km/h).
    /// If implied speed between consecutive accepted points exceeds this,
    /// the newer point is treated as a GPS teleport and rejected.
    static let maxSpeedMs: Double = 14

    /// Filter trackpoints to only those reliable enough for distance/pace calculations.
    ///
    /// Two-stage filter in a single pass:
    /// 1. Accuracy: reject points where err is nil or >= gpsErrThreshold
    /// 2. Speed: reject points that imply impossible speed from the last accepted point
    static func filterReliable(_ trackpoints: [Trackpoint]) -> [Trackpoint] {
        var result: [Trackpoint] = []

        for tp in trackpoints {
            // Stage 1: accuracy filter
            guard let err = tp.err, err < gpsErrThreshold else { continue }

            // Stage 2: speed filter (against last accepted point)
            if let prev = result.last {
                let dist = Geo.haversineMetres(prev.lat, prev.lng, tp.lat, tp.lng)
                guard let prevTime = Formatting.parseISO(prev.createdAt),
                      let thisTime = Formatting.parseISO(tp.createdAt) else { continue }
                let dt = thisTime.timeIntervalSince(prevTime)
                if dt > 0, dist / dt > maxSpeedMs { continue }
            }

            result.append(tp)
        }

        return result
    }
}
