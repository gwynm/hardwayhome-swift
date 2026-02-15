import Foundation
import CoreLocation

/// GPS status quality, matching the trackpoint filter thresholds.
enum GpsStatus: Sendable {
    case none
    case poor   // accuracy >= threshold (points will be filtered out)
    case good   // accuracy < threshold (points used in calculations)
}

/// Manages CoreLocation for foreground/background GPS tracking.
/// Writes trackpoints directly to the database when a workout is active.
@MainActor
@Observable
final class LocationService: NSObject {

    private(set) var gpsStatus: GpsStatus = .none
    private(set) var accuracy: Double? = nil

    private var locationManager: CLLocationManager?
    private var activeWorkoutId: Int64? = nil
    private let db: AppDatabase

    init(db: AppDatabase = .shared) {
        self.db = db
        super.init()
    }

    // MARK: - Permissions

    func requestPermissions() {
        let manager = getOrCreateManager()
        if manager.authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
        } else if manager.authorizationStatus == .authorizedWhenInUse {
            manager.requestAlwaysAuthorization()
        }
    }

    func requestAlwaysPermission() {
        let manager = getOrCreateManager()
        if manager.authorizationStatus != .authorizedAlways {
            manager.requestAlwaysAuthorization()
        }
    }

    var hasWhenInUsePermission: Bool {
        let manager = getOrCreateManager()
        return manager.authorizationStatus == .authorizedWhenInUse
            || manager.authorizationStatus == .authorizedAlways
    }

    var hasAlwaysPermission: Bool {
        let manager = getOrCreateManager()
        return manager.authorizationStatus == .authorizedAlways
    }

    // MARK: - Tracking

    func startTracking(workoutId: Int64) {
        activeWorkoutId = workoutId
        let manager = getOrCreateManager()
        manager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        manager.distanceFilter = 5  // metres
        manager.activityType = .fitness
        manager.allowsBackgroundLocationUpdates = true
        manager.showsBackgroundLocationIndicator = true
        manager.pausesLocationUpdatesAutomatically = false
        manager.startUpdatingLocation()
    }

    func stopTracking() {
        activeWorkoutId = nil
        locationManager?.stopUpdatingLocation()
    }

    // MARK: - Private

    private func getOrCreateManager() -> CLLocationManager {
        if let m = locationManager { return m }
        let m = CLLocationManager()
        m.delegate = self
        locationManager = m
        return m
    }
}

// MARK: - CLLocationManagerDelegate

extension LocationService: CLLocationManagerDelegate {

    nonisolated func locationManager(_ manager: CLLocationManager,
                                     didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in
            for location in locations {
                let acc = location.horizontalAccuracy
                accuracy = acc

                if acc < 0 {
                    gpsStatus = .none
                } else if acc >= TrackpointFilter.gpsErrThreshold {
                    gpsStatus = .poor
                } else {
                    gpsStatus = .good
                }

                // Write trackpoint if workout is active
                if let workoutId = activeWorkoutId {
                    try? db.insertTrackpoint(
                        workoutId: workoutId,
                        lat: location.coordinate.latitude,
                        lng: location.coordinate.longitude,
                        speed: location.speed >= 0 ? location.speed : nil,
                        err: acc >= 0 ? acc : nil)
                }
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager,
                                     didFailWithError error: Error) {
        Task { @MainActor in
            gpsStatus = .none
            accuracy = nil
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            if status == .authorizedWhenInUse {
                // Automatically request Always after WhenInUse is granted
                self.locationManager?.requestAlwaysAuthorization()
            }
        }
    }
}
