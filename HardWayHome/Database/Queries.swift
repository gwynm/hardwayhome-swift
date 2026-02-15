import Foundation
import GRDB

// MARK: - Workout queries

extension AppDatabase {

    /// Get the currently active workout (started but not finished), if any.
    func getActiveWorkout() throws -> Workout? {
        try dbWriter.read { db in
            try Workout
                .filter(Workout.Columns.finishedAt == nil)
                .order(Workout.Columns.startedAt.desc)
                .fetchOne(db)
        }
    }

    /// Create a new workout and return its id.
    func startWorkout() throws -> Int64 {
        try dbWriter.write { db in
            let workout = Workout(startedAt: Date().timeIntervalSince1970)
            try workout.insert(db)
            return db.lastInsertedRowID
        }
    }

    /// Finish a workout: set finished_at and compute cache fields.
    /// Read phase (trackpoints, pulses, filtering, distance) runs outside the write lock
    /// so it doesn't block concurrent inserts from GPS/BLE.
    func finishWorkout(_ workoutId: Int64, trackpointFilter: ([Trackpoint]) -> [Trackpoint]) throws {
        // Read phase — no write lock held
        let allTrackpoints = try getTrackpoints(workoutId)
        let reliable = trackpointFilter(allTrackpoints)
        let distance = Geo.totalDistance(reliable.map { ($0.lat, $0.lng) })

        var avgSecPerKm: Double? = nil
        if distance > 0, reliable.count >= 2 {
            let totalSeconds = reliable.last!.createdAt - reliable.first!.createdAt
            avgSecPerKm = totalSeconds / (distance / 1000)
        }

        let avgBpm = try dbWriter.read { db in
            try Double.fetchOne(db, sql:
                "SELECT AVG(bpm) FROM pulses WHERE workout_id = ?", arguments: [workoutId])
        }

        // Write phase — short, just the UPDATE
        let now = Date().timeIntervalSince1970
        try dbWriter.write { db in
            try db.execute(sql: """
                UPDATE workouts
                SET finished_at = ?, distance = ?, avg_sec_per_km = ?, avg_bpm = ?
                WHERE id = ?
                """, arguments: [now, distance, avgSecPerKm, avgBpm, workoutId])
        }
    }

    /// Delete a workout and all its trackpoints and pulses (cascaded by FK).
    func deleteWorkout(_ workoutId: Int64) throws {
        try dbWriter.write { db in
            try db.execute(sql: "DELETE FROM workouts WHERE id = ?", arguments: [workoutId])
        }
    }

    /// Get a single workout by ID.
    func getWorkout(_ workoutId: Int64) throws -> Workout? {
        try dbWriter.read { db in
            try Workout.fetchOne(db, key: workoutId)
        }
    }

    /// Get all finished workouts, newest first.
    func getWorkoutHistory() throws -> [Workout] {
        try dbWriter.read { db in
            try Workout
                .filter(Workout.Columns.finishedAt != nil)
                .order(Workout.Columns.startedAt.desc)
                .fetchAll(db)
        }
    }
}

// MARK: - Trackpoint queries

extension AppDatabase {

    /// Insert a trackpoint and return the inserted record.
    @discardableResult
    func insertTrackpoint(workoutId: Int64, lat: Double, lng: Double,
                          speed: Double?, err: Double?) throws -> Trackpoint {
        try dbWriter.write { db in
            try Trackpoint(
                workoutId: workoutId,
                createdAt: Date().timeIntervalSince1970,
                lat: lat, lng: lng, speed: speed, err: err)
            .inserted(db)
        }
    }

    /// Get all trackpoints for a workout, ordered by time.
    func getTrackpoints(_ workoutId: Int64) throws -> [Trackpoint] {
        try dbWriter.read { db in
            try Trackpoint
                .filter(Trackpoint.Columns.workoutId == workoutId)
                .order(Trackpoint.Columns.createdAt.asc)
                .fetchAll(db)
        }
    }
}

// MARK: - Pulse queries

extension AppDatabase {

    /// Insert a heart rate pulse reading and return the inserted record.
    @discardableResult
    func insertPulse(workoutId: Int64, bpm: Int) throws -> Pulse {
        try dbWriter.write { db in
            try Pulse(
                workoutId: workoutId,
                createdAt: Date().timeIntervalSince1970,
                bpm: bpm)
            .inserted(db)
        }
    }

    /// Get all pulse readings for a workout, ordered by time.
    func getPulses(_ workoutId: Int64) throws -> [Pulse] {
        try dbWriter.read { db in
            try Pulse
                .filter(Pulse.Columns.workoutId == workoutId)
                .order(Pulse.Columns.createdAt.asc)
                .fetchAll(db)
        }
    }


}

// MARK: - Bulk operations

extension AppDatabase {

    /// Delete all workout data (workouts, trackpoints, pulses via CASCADE).
    func clearAllWorkoutData() throws {
        try dbWriter.write { db in
            try db.execute(sql: "DELETE FROM workouts")
        }
    }
}

// MARK: - KV store

extension AppDatabase {

    func kvGet(_ key: String) throws -> String? {
        try dbWriter.read { db in
            try String.fetchOne(db, sql:
                "SELECT value FROM kv WHERE key = ?", arguments: [key])
        }
    }

    func kvSet(_ key: String, value: String) throws {
        try dbWriter.write { db in
            try db.execute(sql:
                "INSERT OR REPLACE INTO kv (key, value) VALUES (?, ?)",
                arguments: [key, value])
        }
    }

    func kvDelete(_ key: String) throws {
        try dbWriter.write { db in
            try db.execute(sql: "DELETE FROM kv WHERE key = ?", arguments: [key])
        }
    }
}

// MARK: - Database path (for backup)

extension AppDatabase {

    /// The on-disk path to the database file, or nil for in-memory databases.
    var databasePath: String? {
        (dbWriter as? DatabaseQueue).flatMap { queue in
            queue.path == ":memory:" ? nil : queue.path
        }
    }
}
