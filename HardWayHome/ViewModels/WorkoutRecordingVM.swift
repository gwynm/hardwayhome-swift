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

    init(db: AppDatabase = .shared) {
        self.db = db
        self.locationService = LocationService(db: db)
        self.heartRateService = HeartRateService(db: db)
        self.backupService = BackupService(db: db)
    }

    /// Initialize on app launch — request permissions and check for active workout.
    func initialize() async {
        _ = db

        locationService.requestPermissions()
        locationService.startMonitoring()
        heartRateService.initialize()
        backupService.initStatus()

        // Resume active workout if app was killed mid-run
        do {
            if let workout = try db.getActiveWorkout() {
                activeWorkout = workout
                heartRateService.setActiveWorkoutId = workout.id
                locationService.startTracking(workoutId: workout.id!)
            }
        } catch {
            log.error("Failed to check for active workout: \(error)")
        }

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
        } catch {
            log.error("Failed to start workout: \(error)")
        }
    }

    func finish() {
        guard let workout = activeWorkout, let id = workout.id else { return }
        locationService.stopTracking()
        heartRateService.setActiveWorkoutId = nil
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

    func discard() {
        guard let workout = activeWorkout, let id = workout.id else { return }
        locationService.stopTracking()
        heartRateService.setActiveWorkoutId = nil
        do {
            try db.deleteWorkout(id)
        } catch {
            log.error("Failed to delete workout \(id): \(error)")
        }
        activeWorkout = nil
    }
}
