import Foundation

/// Pace calculations over trailing distance windows.
enum PaceCalc {

    /// Compute pace (seconds per km) over a trailing distance window.
    ///
    /// Walks backwards through the trackpoint list to find the point approximately
    /// `windowMetres` ago. Returns sec/km based on the time and distance between
    /// that point and the most recent trackpoint.
    ///
    /// Returns nil if there aren't enough trackpoints to cover the window.
    static func paceOverWindow(_ trackpoints: [Trackpoint], windowMetres: Double) -> Double? {
        guard trackpoints.count >= 2 else { return nil }

        let latest = trackpoints[trackpoints.count - 1]
        var accumulatedDistance = 0.0

        // Walk backwards from the end
        for i in stride(from: trackpoints.count - 2, through: 0, by: -1) {
            let segDist = Geo.haversineMetres(
                trackpoints[i].lat, trackpoints[i].lng,
                trackpoints[i + 1].lat, trackpoints[i + 1].lng)
            accumulatedDistance += segDist

            if accumulatedDistance >= windowMetres {
                guard let latestTime = Formatting.parseISO(latest.createdAt),
                      let startTime = Formatting.parseISO(trackpoints[i].createdAt) else {
                    return nil
                }
                let timeSeconds = latestTime.timeIntervalSince(startTime)
                guard accumulatedDistance > 0, timeSeconds > 0 else { return nil }
                return (timeSeconds / accumulatedDistance) * 1000
            }
        }

        return nil  // Not enough distance covered
    }

    /// Compute total distance in metres from a list of trackpoints.
    static func trackpointDistance(_ trackpoints: [Trackpoint]) -> Double {
        Geo.totalDistance(trackpoints.map { ($0.lat, $0.lng) })
    }
}
