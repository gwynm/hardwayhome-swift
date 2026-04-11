import Foundation
import os

private let log = Logger(subsystem: "com.gwynmorfey.hardwayhome.native", category: "workout")

/// Central view model for workout start/stop/resume lifecycle.
@MainActor
@Observable
final class WorkoutRecordingVM {
    private(set) var activeWorkout: Workout? = nil
    private(set) var isLoading = true
    private(set) var isSaving = false

    private let db: AppDatabase
    let locationService: LocationService
    let heartRateService: HeartRateService
    let backupService: BackupService
    let watchdogService: any Watchdog

    init(db: AppDatabase = .shared, watchdog: (any Watchdog)? = nil) {
        self.db = db
        self.locationService = LocationService(db: db)
        self.heartRateService = HeartRateService(db: db)
        self.backupService = BackupService(db: db)
        self.watchdogService = watchdog ?? WatchdogService()
        self.locationService.watchdog = self.watchdogService
    }

    /// Initialize on app launch — request permissions and check for active workout.
    func initialize() async {
        _ = db

        locationService.requestPermissions()
        locationService.startMonitoring()
        heartRateService.initialize()
        backupService.initStatus()
        await watchdogService.requestPermission()

        checkForRecovery()

        isLoading = false

        let db = self.db
        Task.detached {
            try? db.backfillBestSplitSec(trackpointFilter: TrackpointFilter.filterReliable)
        }
    }

    func start() {
        do {
            let workoutId = try db.startWorkout()
            activeWorkout = try db.getActiveWorkout()
            heartRateService.setActiveWorkoutId = workoutId
            locationService.startTracking(workoutId: workoutId)
            watchdogService.arm()
        } catch {
            log.error("Failed to start workout: \(error)")
        }
    }

    func finish() {
        guard let workout = activeWorkout, let id = workout.id else { return }
        locationService.stopTracking()
        heartRateService.setActiveWorkoutId = nil
        watchdogService.disarm()
        isSaving = true
        let db = self.db
        let backupService = self.backupService
        Task {
            do {
                try await Task.detached {
                    try db.finishWorkout(id, trackpointFilter: TrackpointFilter.filterReliable)
                }.value
            } catch {
                log.error("Failed to finish workout \(id): \(error)")
            }
            isSaving = false
            activeWorkout = nil
            Task.detached { await backupService.backupDatabase() }
        }
    }

    func workoutHistory() throws -> [Workout] {
        try db.getWorkoutHistory()
    }

    /// Re-check the database for an active workout that this VM lost track of.
    func checkForRecovery() {
        guard activeWorkout == nil else { return }
        do {
            if let workout = try db.getActiveWorkout() {
                log.info("Recovering workout \(workout.id!) started at \(workout.startedAt)")
                activeWorkout = workout
                heartRateService.setActiveWorkoutId = workout.id
                locationService.startTracking(workoutId: workout.id!)
                watchdogService.arm()
            }
        } catch {
            log.error("Recovery check failed: \(error)")
        }
    }

    func discard() {
        guard let workout = activeWorkout, let id = workout.id else { return }
        locationService.stopTracking()
        heartRateService.setActiveWorkoutId = nil
        watchdogService.disarm()
        do {
            try db.deleteWorkout(id)
        } catch {
            log.error("Failed to delete workout \(id): \(error)")
        }
        activeWorkout = nil
    }
}
