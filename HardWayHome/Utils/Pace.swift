import Foundation

/// Pace calculations over trailing distance windows.
enum PaceCalc {

    /// Compute pace (seconds per km) over a trailing distance window.
    static func paceOverWindow(_ trackpoints: [Trackpoint], windowMetres: Double) -> Double? {
        guard trackpoints.count >= 2 else { return nil }

        let latest = trackpoints[trackpoints.count - 1]
        var accumulatedDistance = 0.0

        for i in stride(from: trackpoints.count - 2, through: 0, by: -1) {
            let segDist = Geo.haversineMetres(
                trackpoints[i].lat, trackpoints[i].lng,
                trackpoints[i + 1].lat, trackpoints[i + 1].lng)
            accumulatedDistance += segDist

            if accumulatedDistance >= windowMetres {
                let timeSeconds = latest.createdAt - trackpoints[i].createdAt
                guard accumulatedDistance > 0, timeSeconds > 0 else { return nil }
                return (timeSeconds / accumulatedDistance) * 1000
            }
        }

        return nil
    }

    /// Compute total distance in metres from a list of trackpoints.
    static func trackpointDistance(_ trackpoints: [Trackpoint]) -> Double {
        Geo.totalDistance(trackpoints.map { ($0.lat, $0.lng) })
    }
}
