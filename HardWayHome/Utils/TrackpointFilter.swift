import Foundation

/// Trackpoint reliability filtering.
enum TrackpointFilter {
    /// GPS accuracy threshold in metres.
    static let gpsErrThreshold: Double = 20

    /// Maximum plausible speed in m/s (~50 km/h).
    static let maxSpeedMs: Double = 14

    /// Filter trackpoints to only those reliable enough for distance/pace calculations.
    static func filterReliable(_ trackpoints: [Trackpoint]) -> [Trackpoint] {
        var result: [Trackpoint] = []

        for tp in trackpoints {
            guard isReliable(tp, after: result.last) else { continue }
            result.append(tp)
        }

        return result
    }

    /// Check whether a single trackpoint is reliable given the previous reliable point.
    static func isReliable(_ tp: Trackpoint, after lastReliable: Trackpoint?) -> Bool {
        guard let err = tp.err, err < gpsErrThreshold else { return false }

        if let prev = lastReliable {
            let dist = Geo.haversineMetres(prev.lat, prev.lng, tp.lat, tp.lng)
            let dt = tp.createdAt - prev.createdAt
            if dt > 0, dist / dt > maxSpeedMs { return false }
        }

        return true
    }
}
