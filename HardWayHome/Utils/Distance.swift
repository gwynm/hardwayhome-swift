import Foundation

/// Geographic distance calculations.
enum Geo {
    /// Earth radius in metres.
    private static let earthRadiusM: Double = 6_371_000

    /// Haversine distance in metres between two lat/lng points.
    static func haversineMetres(_ lat1: Double, _ lng1: Double,
                                _ lat2: Double, _ lng2: Double) -> Double {
        let dLat = (lat2 - lat1) * .pi / 180
        let dLng = (lng2 - lng1) * .pi / 180
        let rLat1 = lat1 * .pi / 180
        let rLat2 = lat2 * .pi / 180
        let a = sin(dLat / 2) * sin(dLat / 2)
            + cos(rLat1) * cos(rLat2) * sin(dLng / 2) * sin(dLng / 2)
        return earthRadiusM * 2 * atan2(sqrt(a), sqrt(1 - a))
    }

    /// Compute total distance in metres from a list of (lat, lng) points.
    static func totalDistance(_ points: [(Double, Double)]) -> Double {
        guard points.count >= 2 else { return 0 }
        var total = 0.0
        for i in 1..<points.count {
            total += haversineMetres(points[i - 1].0, points[i - 1].1,
                                     points[i].0, points[i].1)
        }
        return total
    }
}
