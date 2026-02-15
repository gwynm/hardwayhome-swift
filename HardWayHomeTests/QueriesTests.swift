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
        let base = epoch("2026-02-13T11:30:00Z")
        for i in 0..<10 {
            let lat = 51.5000 + Double(i) * 0.001
            try db.dbWriter.write { conn in
                try conn.execute(sql: """
                    INSERT INTO trackpoints (workout_id, created_at, lat, lng, speed, err)
                    VALUES (?, ?, ?, ?, ?, ?)
                    """, arguments: [id, base + Double(i * 10), lat, -0.100, 3.0, 5.0])
            }
        }

        // Insert some pulses
        for i in 0..<5 {
            try db.dbWriter.write { conn in
                try conn.execute(sql: """
                    INSERT INTO pulses (workout_id, created_at, bpm)
                    VALUES (?, ?, ?)
                    """, arguments: [id, base + Double(i * 10), 140 + i])
            }
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
        try db.insertTrackpoint(workoutId: id, lat: 51.5, lng: -0.1, speed: nil, err: 5)
        try db.insertPulse(workoutId: id, bpm: 140)

        try db.deleteWorkout(id)

        #expect(try db.getWorkout(id) == nil)
        #expect(try db.getTrackpoints(id).isEmpty)
        #expect(try db.getPulses(id).isEmpty)
    }

    @Test("Workout history returns only finished, newest first")
    func workoutHistory() throws {
        let db = try makeDB()

        let id1 = try db.dbWriter.write { conn -> Int64 in
            var w = Workout(startedAt: epoch("2026-02-13T10:00:00Z"))
            try w.insert(conn)
            return conn.lastInsertedRowID
        }
        try db.finishWorkout(id1, trackpointFilter: { $0 })

        let id2 = try db.dbWriter.write { conn -> Int64 in
            var w = Workout(startedAt: epoch("2026-02-13T11:00:00Z"))
            try w.insert(conn)
            return conn.lastInsertedRowID
        }
        try db.finishWorkout(id2, trackpointFilter: { $0 })

        // Active workout — should not appear in history
        _ = try db.startWorkout()

        let history = try db.getWorkoutHistory()
        #expect(history.count == 2)
        #expect(history[0].id == id2)
        #expect(history[1].id == id1)
    }

    @Test("KV store round-trip")
    func kvStore() throws {
        let db = try makeDB()

        #expect(try db.kvGet("test_key") == nil)

        try db.kvSet("test_key", value: "hello")
        #expect(try db.kvGet("test_key") == "hello")

        try db.kvSet("test_key", value: "world")
        #expect(try db.kvGet("test_key") == "world")

        try db.kvDelete("test_key")
        #expect(try db.kvGet("test_key") == nil)
    }

    @Test("Trackpoints ordered by time")
    func trackpointOrdering() throws {
        let db = try makeDB()
        let id = try db.startWorkout()

        let base = epoch("2026-02-13T11:30:00Z")
        try db.dbWriter.write { conn in
            try conn.execute(sql: "INSERT INTO trackpoints (workout_id, created_at, lat, lng, err) VALUES (?, ?, 51.5, -0.1, 5)", arguments: [id, base + 20])
            try conn.execute(sql: "INSERT INTO trackpoints (workout_id, created_at, lat, lng, err) VALUES (?, ?, 51.5, -0.1, 5)", arguments: [id, base])
            try conn.execute(sql: "INSERT INTO trackpoints (workout_id, created_at, lat, lng, err) VALUES (?, ?, 51.5, -0.1, 5)", arguments: [id, base + 10])
        }

        let tps = try db.getTrackpoints(id)
        #expect(tps.count == 3)
        #expect(tps[0].createdAt == base)
        #expect(tps[1].createdAt == base + 10)
        #expect(tps[2].createdAt == base + 20)
    }
}
