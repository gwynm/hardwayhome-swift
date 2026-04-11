import HealthKit
import os

private let log = Logger(subsystem: "com.gwynmorfey.hardwayhome.native", category: "hk-session")

/// Wraps an HKWorkoutSession to give the app elevated background priority
/// during workouts. iOS is far less likely to kill an app with an active
/// workout session. We keep all real data in our own SQLite DB — HealthKit
/// is used only for process priority and (optionally) writing the finished
/// workout to Apple Health.
@MainActor
@Observable
final class WorkoutSessionService {

    private let healthStore = HKHealthStore()
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?

    func requestAuthorization() async {
        guard HKHealthStore.isHealthDataAvailable() else {
            log.warning("HealthKit not available on this device")
            return
        }
        let types: Set<HKSampleType> = [HKWorkoutType.workoutType()]
        do {
            try await healthStore.requestAuthorization(toShare: types, read: [])
        } catch {
            log.error("HealthKit authorization failed: \(error)")
        }
    }

    func startSession() {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        guard session == nil else { return }

        let config = HKWorkoutConfiguration()
        config.activityType = .running
        config.locationType = .outdoor

        do {
            let s = try HKWorkoutSession(healthStore: healthStore, configuration: config)
            let b = s.associatedWorkoutBuilder()
            b.dataSource = HKLiveWorkoutDataSource(healthStore: healthStore,
                                                   workoutConfiguration: config)
            s.startActivity(with: Date())
            Task {
                try? await b.beginCollection(at: Date())
            }
            session = s
            builder = b
            log.info("HKWorkoutSession started")
        } catch {
            log.error("Failed to start HKWorkoutSession: \(error)")
        }
    }

    func endSession() async {
        guard let session, let builder else {
            self.session = nil
            self.builder = nil
            return
        }
        session.end()
        do {
            try await builder.endCollection(at: Date())
            try await builder.finishWorkout()
            log.info("HKWorkoutSession ended and workout saved to Health")
        } catch {
            log.error("Failed to end HKWorkoutSession: \(error)")
        }
        self.session = nil
        self.builder = nil
    }
}
