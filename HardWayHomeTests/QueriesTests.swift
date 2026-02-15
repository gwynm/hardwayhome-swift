import Testing
@testable import HardWayHome

@Suite("Database Queries")
struct QueriesTests {

    private func makeDB() throws -> AppDatabase {
        try AppDatabase.empty()
    }

    @Test("Start and get active workout")
    func startWorkout() throws {
        let db = try makeDB()
        let id = try db.startWorkout()
        #expect(id > 0)

        let active = try db.getActiveWorkout()
        #expect(active != nil)
        #expect(active?.id == id)
        #expect(active?.finishedAt == nil)
    }

    @Test("No active workout initially")
    func noActiveWorkout() throws {
        let db = try makeDB()
        let active = try db.getActiveWorkout()
        #expect(active == nil)
    }

    @Test("Finish workout sets finished_at and computes fields")
    func finishWorkout() throws {
        let db = try makeDB()
        let id = try db.startWorkout()

        // Insert some trackpoints (~111m apart each, 10 points)
        for i in 0..<10 {
            let lat = 51.5000 + Double(i) * 0.001
            let seconds = i * 10
            let ts = "2026-02-13T11:\(String(format: "%02d", 30 + seconds / 60)):\(String(format: "%02d", seconds % 60))Z"
            try db.insertTrackpoint(workoutId: id, createdAt: ts,
                                    lat: lat, lng: -0.100, speed: 3.0, err: 5)
        }

        // Insert some pulses
        for i in 0..<5 {
            let ts = "2026-02-13T11:30:\(String(format: "%02d", i * 10))Z"
            try db.insertPulse(workoutId: id, createdAt: ts, bpm: 140 + i)
        }

        try db.finishWorkout(id, trackpointFilter: TrackpointFilter.filterReliable)

        let workout = try db.getWorkout(id)
        #expect(workout?.finishedAt != nil)
        #expect(workout?.distance != nil)
        #expect(workout?.distance ?? 0 > 900)  // ~1km
        #expect(workout?.avgBpm != nil)

        // No longer active
        let active = try db.getActiveWorkout()
        #expect(active == nil)
    }

    @Test("Delete workout removes everything")
    func deleteWorkout() throws {
        let db = try makeDB()
        let id = try db.startWorkout()
        try db.insertTrackpoint(workoutId: id, createdAt: "2026-02-13T11:30:00Z",
                                lat: 51.5, lng: -0.1, speed: nil, err: 5)
        try db.insertPulse(workoutId: id, createdAt: "2026-02-13T11:30:00Z", bpm: 140)

        try db.deleteWorkout(id)

        #expect(try db.getWorkout(id) == nil)
        #expect(try db.getTrackpoints(id).isEmpty)
        #expect(try db.getPulses(id).isEmpty)
    }

    @Test("Workout history returns only finished, newest first")
    func workoutHistory() throws {
        let db = try makeDB()

        // Insert workouts with explicit different timestamps to guarantee ordering
        let id1 = try db.dbWriter.write { db -> Int64 in
            var w = Workout(startedAt: "2026-02-13T10:00:00Z")
            try w.insert(db)
            return db.lastInsertedRowID
        }
        try db.finishWorkout(id1, trackpointFilter: { $0 })

        let id2 = try db.dbWriter.write { db -> Int64 in
            var w = Workout(startedAt: "2026-02-13T11:00:00Z")
            try w.insert(db)
            return db.lastInsertedRowID
        }
        try db.finishWorkout(id2, trackpointFilter: { $0 })

        // Active workout — should not appear in history
        _ = try db.startWorkout()

        let history = try db.getWorkoutHistory()
        #expect(history.count == 2)
        // Newest first
        #expect(history[0].id == id2)
        #expect(history[1].id == id1)
    }

    @Test("KV store round-trip")
    func kvStore() throws {
        let db = try makeDB()

        // Initially nil
        #expect(try db.kvGet("test_key") == nil)

        // Set and get
        try db.kvSet("test_key", value: "hello")
        #expect(try db.kvGet("test_key") == "hello")

        // Overwrite
        try db.kvSet("test_key", value: "world")
        #expect(try db.kvGet("test_key") == "world")

        // Delete
        try db.kvDelete("test_key")
        #expect(try db.kvGet("test_key") == nil)
    }

    @Test("Trackpoints ordered by time")
    func trackpointOrdering() throws {
        let db = try makeDB()
        let id = try db.startWorkout()

        try db.insertTrackpoint(workoutId: id, createdAt: "2026-02-13T11:30:20Z",
                                lat: 51.5, lng: -0.1, speed: nil, err: 5)
        try db.insertTrackpoint(workoutId: id, createdAt: "2026-02-13T11:30:00Z",
                                lat: 51.5, lng: -0.1, speed: nil, err: 5)
        try db.insertTrackpoint(workoutId: id, createdAt: "2026-02-13T11:30:10Z",
                                lat: 51.5, lng: -0.1, speed: nil, err: 5)

        let tps = try db.getTrackpoints(id)
        #expect(tps.count == 3)
        #expect(tps[0].createdAt == "2026-02-13T11:30:00Z")
        #expect(tps[1].createdAt == "2026-02-13T11:30:10Z")
        #expect(tps[2].createdAt == "2026-02-13T11:30:20Z")
    }
}
