import Foundation

/// Trackpoint reliability filtering.
enum TrackpointFilter {
    /// GPS accuracy threshold in metres.
    static let gpsErrThreshold: Double = 20

    /// Maximum plausible speed in m/s (~50 km/h).
    static let maxSpeedMs: Double = 14

    // MARK: - GPS-drift (un-acquired fix) detection
    //
    // When a fix is poor — the app is started indoors, or the user steps into a
    // building mid-walk — the receiver reports a position that scribbles around
    // instead of tracking real movement. Each individual jump can stay under the
    // per-point accuracy/speed limits above, yet they accumulate into hundreds of
    // metres of phantom distance and a tangled route. The tell is *local
    // incoherence*: over a short run of consecutive points the net displacement is
    // far smaller than the path walked through them. Real walking is locally
    // straight even when the overall route doubles back, so this is measured over a
    // small point-count window rather than over the whole track.

    /// Half-width of the coherence window, in points (window spans up to 2N+1 points).
    static let driftWindowHalf = 3

    /// Net-displacement / path-length below this marks a window as drift.
    static let driftCoherenceThreshold: Double = 0.5

    /// Minimum path length (m) in a window before it can be judged drift — keeps a
    /// genuine standstill (good fix, tiny jitter, ~no phantom distance) from being flagged.
    static let driftMinPathMetres: Double = 15

    /// Filter trackpoints to only those reliable enough for distance/pace calculations.
    static func filterReliable(_ trackpoints: [Trackpoint]) -> [Trackpoint] {
        var result: [Trackpoint] = []

        for tp in withoutDrift(trackpoints) {
            guard isReliable(tp, after: result.last) else { continue }
            result.append(tp)
        }

        return result
    }

    /// Drop points sitting in a locally-incoherent (GPS-drift) neighbourhood.
    /// Runs before the per-point checks so phantom-movement clusters — at the start
    /// of a walk or anywhere a fix degrades mid-walk — don't reach distance/splits.
    static func withoutDrift(_ trackpoints: [Trackpoint]) -> [Trackpoint] {
        let n = trackpoints.count
        guard n >= 3 else { return trackpoints }

        var keep = [Bool](repeating: true, count: n)
        for i in 0..<n {
            let lo = max(0, i - driftWindowHalf)
            let hi = min(n - 1, i + driftWindowHalf)
            guard hi - lo >= 2 else { continue }

            var path = 0.0
            for j in lo..<hi {
                path += Geo.haversineMetres(trackpoints[j].lat, trackpoints[j].lng,
                                            trackpoints[j + 1].lat, trackpoints[j + 1].lng)
            }
            guard path > driftMinPathMetres else { continue }

            let net = Geo.haversineMetres(trackpoints[lo].lat, trackpoints[lo].lng,
                                          trackpoints[hi].lat, trackpoints[hi].lng)
            if net / path < driftCoherenceThreshold { keep[i] = false }
        }

        return zip(trackpoints, keep).compactMap { $1 ? $0 : nil }
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
