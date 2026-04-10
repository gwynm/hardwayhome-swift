import Testing
@testable import HardWayHome

@Suite("Workout Recovery")
struct RecoveryTests {

    private func makeDB() throws -> AppDatabase {
        try AppDatabase.empty()
    }

    @Test("getActiveWorkout finds unfinished workout after simulated crash")
    func activeWorkoutSurvivesCrash() throws {
        let db = try makeDB()
        let id = try db.startWorkout()

        // Simulate crash: just drop the in-memory "VM state".
        // The workout row still has finished_at = NULL.
        let recovered = try db.getActiveWorkout()
        #expect(recovered != nil)
        #expect(recovered?.id == id)
        #expect(recovered?.finishedAt == nil)
    }

    @Test("getActiveWorkout returns nil after explicit finish")
    func noRecoveryAfterFinish() throws {
        let db = try makeDB()
        let id = try db.startWorkout()
        try db.finishWorkout(id, trackpointFilter: { $0 })

        let recovered = try db.getActiveWorkout()
        #expect(recovered == nil)
    }

    @Test("getActiveWorkout returns nil after discard")
    func noRecoveryAfterDiscard() throws {
        let db = try makeDB()
        let id = try db.startWorkout()
        try db.deleteWorkout(id)

        let recovered = try db.getActiveWorkout()
        #expect(recovered == nil)
    }

    @Test("checkForRecovery restores active workout on VM")
    @MainActor func checkForRecoveryRestores() throws {
        let db = try makeDB()
        let id = try db.startWorkout()

        // Create a fresh VM (simulating app relaunch) — activeWorkout starts nil
        let vm = WorkoutRecordingVM(db: db)
        #expect(vm.activeWorkout == nil)

        vm.checkForRecovery()

        #expect(vm.activeWorkout != nil)
        #expect(vm.activeWorkout?.id == id)
    }

    @Test("checkForRecovery is a no-op when workout already active")
    @MainActor func checkForRecoveryNoOpWhenActive() throws {
        let db = try makeDB()

        let vm = WorkoutRecordingVM(db: db)
        vm.start()
        let originalId = vm.activeWorkout?.id

        // Start a second workout directly in the DB (orphan)
        _ = try db.startWorkout()

        // Recovery should not overwrite the existing active workout
        vm.checkForRecovery()
        #expect(vm.activeWorkout?.id == originalId)
    }

    @Test("checkForRecovery is a no-op when no active workout exists")
    @MainActor func checkForRecoveryNoOpWhenEmpty() throws {
        let db = try makeDB()
        let vm = WorkoutRecordingVM(db: db)

        vm.checkForRecovery()
        #expect(vm.activeWorkout == nil)
    }

    @Test("Recovered workout still has trackpoints and pulses intact")
    func dataIntactAfterCrash() throws {
        let db = try makeDB()
        let id = try db.startWorkout()

        try db.insertTrackpoint(workoutId: id, lat: 51.5, lng: -0.1, speed: 3.0, err: 5.0)
        try db.insertTrackpoint(workoutId: id, lat: 51.501, lng: -0.1, speed: 3.0, err: 5.0)
        try db.insertPulse(workoutId: id, bpm: 145)
        try db.insertPulse(workoutId: id, bpm: 150)

        // Simulate crash + recovery: workout found, data still there
        let recovered = try db.getActiveWorkout()
        #expect(recovered?.id == id)

        let trackpoints = try db.getTrackpoints(id)
        #expect(trackpoints.count == 2)

        let pulses = try db.getPulses(id)
        #expect(pulses.count == 2)
    }

    @Test("Multiple unfinished workouts: recovery picks the newest")
    func recoveryPicksNewest() throws {
        let db = try makeDB()

        // Insert two unfinished workouts with different start times
        let oldId = try db.dbWriter.write { conn -> Int64 in
            let w = Workout(startedAt: epoch("2026-01-01T10:00:00Z"))
            try w.insert(conn)
            return conn.lastInsertedRowID
        }
        let newId = try db.dbWriter.write { conn -> Int64 in
            let w = Workout(startedAt: epoch("2026-04-10T10:00:00Z"))
            try w.insert(conn)
            return conn.lastInsertedRowID
        }

        let recovered = try db.getActiveWorkout()
        #expect(recovered?.id == newId)
        #expect(recovered?.id != oldId)
    }
}
