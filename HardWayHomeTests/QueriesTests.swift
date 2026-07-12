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
            let w = Workout(startedAt: epoch("2026-02-13T10:00:00Z"))
            try w.insert(conn)
            return conn.lastInsertedRowID
        }
        try db.finishWorkout(id1, trackpointFilter: { $0 })

        let id2 = try db.dbWriter.write { conn -> Int64 in
            let w = Workout(startedAt: epoch("2026-02-13T11:00:00Z"))
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

    @Test("finishWorkout computes checkpoint for qualifying workout")
    func finishWorkoutCheckpoint() throws {
        let db = try makeDB()
        let id = try db.startWorkout()

        // Insert 60 trackpoints ~111m apart (each 0.001 lat), 300s per km = 5:00 pace
        // 6 km worth → should get checkpoint "6 x 5:00" (pace 300s)
        let base = epoch("2026-04-10T08:00:00Z")
        for i in 0..<60 {
            let lat = 51.5000 + Double(i) * 0.001
            let t = base + Double(i) * 30 // ~30s between points, ~300s per km
            try db.dbWriter.write { conn in
                try Trackpoint(workoutId: id, createdAt: t, lat: lat, lng: -0.1, speed: 3.0, err: 5.0)
                    .insert(conn)
            }
        }

        try db.finishWorkout(id, trackpointFilter: { $0 })
        let workout = try db.getWorkout(id)!
        #expect(workout.checkpointCount != nil)
        #expect(workout.checkpointCount! >= 5)
        #expect(workout.checkpointPaceSec != nil)
        #expect(workout.checkpointPaceSec! <= 480) // must be ≤ 8:00
    }

    @Test("finishWorkout sets nil checkpoint for short workout")
    func finishWorkoutNoCheckpoint() throws {
        let db = try makeDB()
        let id = try db.startWorkout()

        // Only 3 trackpoints (~222 m) — won't produce any splits
        let base = epoch("2026-04-10T08:00:00Z")
        for i in 0..<3 {
            try db.insertTrackpoint(workoutId: id, lat: 51.5 + Double(i) * 0.001,
                                    lng: -0.1, speed: 3.0, err: 5.0)
        }

        try db.finishWorkout(id, trackpointFilter: { $0 })
        let workout = try db.getWorkout(id)!
        #expect(workout.checkpointCount == nil)
        #expect(workout.checkpointPaceSec == nil)
    }

    @Test("backfill populates checkpoint for existing workouts")
    func backfillCheckpoint() throws {
        let db = try makeDB()

        // Create a finished workout without checkpoint (simulate pre-v7 data)
        let id = try db.dbWriter.write { conn -> Int64 in
            var w = Workout(startedAt: epoch("2026-04-10T08:00:00Z"),
                            finishedAt: epoch("2026-04-10T09:00:00Z"),
                            distance: 6000)
            try w.insert(conn)
            return conn.lastInsertedRowID
        }

        // Add 60 trackpoints for ~6km at ~5:00/km
        let base = epoch("2026-04-10T08:00:00Z")
        for i in 0..<60 {
            try db.dbWriter.write { conn in
                try Trackpoint(workoutId: id, createdAt: base + Double(i) * 30,
                               lat: 51.5 + Double(i) * 0.001, lng: -0.1, speed: 3.0, err: 5.0)
                    .insert(conn)
            }
        }

        try db.backfillBestSplitSec(trackpointFilter: { $0 })
        let workout = try db.getWorkout(id)!
        #expect(workout.checkpointCount != nil)
        #expect(workout.checkpointPaceSec != nil)
    }

    @Test("recompute rewrites stale cached fields, then is gated by its flag")
    func recomputeDerivedFields() throws {
        let db = try makeDB()

        // A finished workout with a deliberately wrong cached distance, plus a clean
        // straight ~1 km of trackpoints (10 points, 0.001° lat ≈ 111 m apart).
        let id = try db.dbWriter.write { conn -> Int64 in
            var w = Workout(startedAt: epoch("2026-04-10T08:00:00Z"),
                            finishedAt: epoch("2026-04-10T09:00:00Z"),
                            distance: 99_999)
            try w.insert(conn)
            return conn.lastInsertedRowID
        }
        let base = epoch("2026-04-10T08:00:00Z")
        for i in 0..<10 {
            try db.dbWriter.write { conn in
                try Trackpoint(workoutId: id, createdAt: base + Double(i * 10),
                               lat: 51.5 + Double(i) * 0.001, lng: -0.1, speed: 3.0, err: 5.0)
                    .insert(conn)
            }
        }

        try db.recomputeDerivedFieldsIfNeeded(trackpointFilter: TrackpointFilter.filterReliable)
        let fixed = try db.getWorkout(id)!.distance ?? 0
        #expect(fixed > 900 && fixed < 1100)  // corrected to ~1 km, not 99_999

        // Tamper again; a second run is a no-op because the flag is now set.
        try db.dbWriter.write { conn in
            try conn.execute(sql: "UPDATE workouts SET distance = 88888 WHERE id = ?",
                             arguments: [id])
        }
        try db.recomputeDerivedFieldsIfNeeded(trackpointFilter: TrackpointFilter.filterReliable)
        #expect(try db.getWorkout(id)!.distance == 88888)
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
