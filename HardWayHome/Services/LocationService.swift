import Foundation
import CoreLocation
import os

private let log = Logger(subsystem: "com.gwynmorfey.hardwayhome.native", category: "location")

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

    /// Called on the main actor after a trackpoint is successfully inserted.
    var onTrackpointInserted: ((Trackpoint) -> Void)?

    private var locationManager: CLLocationManager?
    private var activeWorkoutId: Int64? = nil
    private let db: AppDatabase

    init(db: AppDatabase = .shared) {
        self.db = db
        super.init()
    }

    // MARK: - Permissions

    /// Request When-In-Use on startup. Always is requested later when starting a workout.
    func requestPermissions() {
        let manager = getOrCreateManager()
        if manager.authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
        }
    }

    /// Escalate to Always permission (needed for background tracking during workouts).
    func requestAlwaysPermission() {
        let manager = getOrCreateManager()
        if manager.authorizationStatus == .authorizedWhenInUse {
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

    // MARK: - Monitoring (foreground, for GPS status display)

    /// Start high-accuracy location updates so the GPS status pill is correct.
    /// Called on launch — does not record trackpoints (no activeWorkoutId).
    func startMonitoring() {
        let manager = getOrCreateManager()
        guard manager.authorizationStatus == .authorizedWhenInUse
                || manager.authorizationStatus == .authorizedAlways else { return }
        manager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        manager.distanceFilter = 5
        manager.activityType = .fitness
        manager.pausesLocationUpdatesAutomatically = false
        manager.allowsBackgroundLocationUpdates = false
        manager.showsBackgroundLocationIndicator = false
        manager.startUpdatingLocation()
    }

    // MARK: - Tracking (active workout)

    func startTracking(workoutId: Int64) {
        activeWorkoutId = workoutId
        let manager = getOrCreateManager()
        // Escalate to Always for background tracking if needed
        if manager.authorizationStatus == .authorizedWhenInUse {
            manager.requestAlwaysAuthorization()
        }
        manager.allowsBackgroundLocationUpdates = true
        manager.showsBackgroundLocationIndicator = true
        manager.startUpdatingLocation()
    }

    func stopTracking() {
        activeWorkoutId = nil
        // Disable background updates but keep monitoring for status
        locationManager?.allowsBackgroundLocationUpdates = false
        locationManager?.showsBackgroundLocationIndicator = false
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
                    do {
                        let tp = try db.insertTrackpoint(
                            workoutId: workoutId,
                            lat: location.coordinate.latitude,
                            lng: location.coordinate.longitude,
                            speed: location.speed >= 0 ? location.speed : nil,
                            err: acc >= 0 ? acc : nil)
                        onTrackpointInserted?(tp)
                    } catch {
                        log.error("Failed to insert trackpoint: \(error)")
                    }
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
            if status == .authorizedWhenInUse || status == .authorizedAlways {
                // Start monitoring as soon as we have any permission
                if activeWorkoutId == nil { startMonitoring() }
            }
        }
    }
}
