import Foundation

/// Central view model for workout start/stop/resume lifecycle.
@MainActor
@Observable
final class WorkoutRecordingVM {
    private(set) var activeWorkout: Workout? = nil
    private(set) var isLoading = true

    private let db: AppDatabase
    let locationService: LocationService
    let heartRateService: HeartRateService
    let backupService: BackupService

    init(db: AppDatabase = .shared) {
        self.db = db
        self.locationService = LocationService(db: db)
        self.heartRateService = HeartRateService(db: db)
        self.backupService = BackupService(db: db)
    }

    /// Initialize on app launch — check for active workout.
    /// Permissions are requested lazily when starting a workout (better UX).
    func initialize() async {
        // Initialize database (shared instance triggers migration)
        _ = db

        // Initialize BLE (does not trigger permission dialog)
        heartRateService.initialize()

        // Initialize backup status
        backupService.initStatus()

        // Auto-reconnect to last HR monitor
        heartRateService.reconnectToLastDevice()

        // Check for active workout (resume after kill)
        if let workout = try? db.getActiveWorkout() {
            activeWorkout = workout
            heartRateService.setActiveWorkoutId = workout.id
            locationService.startTracking(workoutId: workout.id!)
        }

        isLoading = false
    }

    func start() {
        // Request location permission if not yet granted
        if !locationService.hasWhenInUsePermission {
            locationService.requestPermissions()
            // Permission dialog will appear — actual start deferred
            // For now, start anyway; tracking will begin once permission is granted
        }

        guard let workoutId = try? db.startWorkout() else { return }
        activeWorkout = try? db.getActiveWorkout()
        heartRateService.setActiveWorkoutId = workoutId
        locationService.startTracking(workoutId: workoutId)
    }

    func finish() {
        guard let workout = activeWorkout, let id = workout.id else { return }
        locationService.stopTracking()
        heartRateService.setActiveWorkoutId = nil
        try? db.finishWorkout(id, trackpointFilter: TrackpointFilter.filterReliable)
        activeWorkout = nil

        // Backup (non-blocking)
        Task { await backupService.backupDatabase() }
    }

    func discard() {
        guard let workout = activeWorkout, let id = workout.id else { return }
        locationService.stopTracking()
        heartRateService.setActiveWorkoutId = nil
        try? db.deleteWorkout(id)
        activeWorkout = nil
    }
}
