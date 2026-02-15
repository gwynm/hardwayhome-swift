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

    /// Initialize on app launch — request permissions and check for active workout.
    func initialize() async {
        // Initialize database (shared instance triggers migration)
        _ = db

        // Request GPS + BLE permissions upfront so status pills are live
        locationService.requestPermissions()
        locationService.startMonitoring()
        heartRateService.initialize()

        // Initialize backup status
        backupService.initStatus()

        // Check for active workout (resume after kill)
        if let workout = try? db.getActiveWorkout() {
            activeWorkout = workout
            heartRateService.setActiveWorkoutId = workout.id
            locationService.startTracking(workoutId: workout.id!)
        }

        isLoading = false
    }

    func start() {
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
