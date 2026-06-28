import Foundation
import GRDB

/// Cached derived fields computed from a workout's reliable trackpoints and pulses.
/// `avg_bpm` is intentionally excluded — it's independent of the trackpoint filter.
struct DerivedFields {
    var distance: Double
    var avgSecPerKm: Double?
    var bestSplitSec: Double?
    var checkpointCount: Int?
    var checkpointPaceSec: Double?
}

// MARK: - Workout queries

extension AppDatabase {

    /// Single source of truth for a workout's cached fields, shared by finish, merge,
    /// and the one-time recompute pass so they can never drift apart.
    static func computeDerivedFields(
        trackpoints: [Trackpoint], pulses: [Pulse],
        trackpointFilter: ([Trackpoint]) -> [Trackpoint]
    ) -> DerivedFields {
        let reliable = trackpointFilter(trackpoints)
        let distance = Geo.totalDistance(reliable.map { ($0.lat, $0.lng) })

        var avgSecPerKm: Double? = nil
        if distance > 0, reliable.count >= 2 {
            let totalSeconds = reliable.last!.createdAt - reliable.first!.createdAt
            avgSecPerKm = totalSeconds / (distance / 1000)
        }

        let splits = SplitCalc.computeKmSplits(trackpoints: reliable, pulses: pulses)
        let checkpoint = SplitCalc.computeCheckpoint(splits: splits)
        return DerivedFields(
            distance: distance, avgSecPerKm: avgSecPerKm,
            bestSplitSec: splits.map(\.seconds).min(),
            checkpointCount: checkpoint?.count, checkpointPaceSec: checkpoint?.paceSec)
    }

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
        let pulses = try getPulses(workoutId)
        let derived = Self.computeDerivedFields(
            trackpoints: allTrackpoints, pulses: pulses, trackpointFilter: trackpointFilter)

        let avgBpm = try dbWriter.read { db in
            try Double.fetchOne(db, sql:
                "SELECT AVG(bpm) FROM pulses WHERE workout_id = ?", arguments: [workoutId])
        }

        // Write phase — short, just the UPDATE
        let now = Date().timeIntervalSince1970
        try dbWriter.write { db in
            try db.execute(sql: """
                UPDATE workouts
                SET finished_at = ?, distance = ?, avg_sec_per_km = ?, avg_bpm = ?,
                    best_split_sec = ?, checkpoint_count = ?, checkpoint_pace_sec = ?
                WHERE id = ?
                """, arguments: [now, derived.distance, derived.avgSecPerKm, avgBpm,
                                 derived.bestSplitSec, derived.checkpointCount,
                                 derived.checkpointPaceSec, workoutId])
        }
    }

    /// Backfill best_split_sec and checkpoint for finished workouts that don't have them yet.
    func backfillBestSplitSec(trackpointFilter: ([Trackpoint]) -> [Trackpoint]) throws {
        let ids: [Int64] = try dbWriter.read { db in
            try Int64.fetchAll(db, sql:
                """
                SELECT id FROM workouts
                WHERE finished_at IS NOT NULL
                  AND (best_split_sec IS NULL OR checkpoint_count IS NULL)
                """)
        }
        for id in ids {
            let trackpoints = try getTrackpoints(id)
            let pulses = try getPulses(id)
            let reliable = trackpointFilter(trackpoints)
            let splits = SplitCalc.computeKmSplits(trackpoints: reliable, pulses: pulses)
            let best = splits.map(\.seconds).min()
            let checkpoint = SplitCalc.computeCheckpoint(splits: splits)
            try dbWriter.write { db in
                try db.execute(sql: """
                    UPDATE workouts
                    SET best_split_sec = COALESCE(best_split_sec, ?),
                        checkpoint_count = ?, checkpoint_pace_sec = ?
                    WHERE id = ?
                    """, arguments: [best, checkpoint?.count, checkpoint?.paceSec, id])
            }
        }
    }

    /// Get the finished workout immediately before the given workout (by start time).
    func getPreviousWorkout(_ workoutId: Int64) throws -> Workout? {
        try dbWriter.read { db in
            guard let workout = try Workout.fetchOne(db, key: workoutId) else { return nil }
            return try Workout
                .filter(Workout.Columns.finishedAt != nil)
                .filter(Workout.Columns.startedAt < workout.startedAt)
                .order(Workout.Columns.startedAt.desc)
                .fetchOne(db)
        }
    }

    /// Merge a workout into a previous one: reassign trackpoints/pulses, recalculate cache fields,
    /// then delete the source workout.
    func mergeWorkout(_ sourceId: Int64, into targetId: Int64,
                      trackpointFilter: ([Trackpoint]) -> [Trackpoint]) throws {
        // Reassign trackpoints and pulses from source to target
        try dbWriter.write { db in
            try db.execute(sql:
                "UPDATE trackpoints SET workout_id = ? WHERE workout_id = ?",
                arguments: [targetId, sourceId])
            try db.execute(sql:
                "UPDATE pulses SET workout_id = ? WHERE workout_id = ?",
                arguments: [targetId, sourceId])
            try db.execute(sql:
                "DELETE FROM workouts WHERE id = ?", arguments: [sourceId])
        }

        // Recalculate cache fields on the merged workout (same logic as finishWorkout)
        let allTrackpoints = try getTrackpoints(targetId)
        let pulses = try getPulses(targetId)
        let derived = Self.computeDerivedFields(
            trackpoints: allTrackpoints, pulses: pulses, trackpointFilter: trackpointFilter)

        let avgBpm = try dbWriter.read { db in
            try Double.fetchOne(db, sql:
                "SELECT AVG(bpm) FROM pulses WHERE workout_id = ?", arguments: [targetId])
        }

        // Update finished_at to the latest trackpoint time (end of merged workout)
        let finishedAt = allTrackpoints.last?.createdAt
            ?? pulses.last?.createdAt
            ?? Date().timeIntervalSince1970

        try dbWriter.write { db in
            try db.execute(sql: """
                UPDATE workouts
                SET finished_at = ?, distance = ?, avg_sec_per_km = ?, avg_bpm = ?,
                    best_split_sec = ?, checkpoint_count = ?, checkpoint_pace_sec = ?
                WHERE id = ?
                """, arguments: [finishedAt, derived.distance, derived.avgSecPerKm, avgBpm,
                                 derived.bestSplitSec, derived.checkpointCount,
                                 derived.checkpointPaceSec, targetId])
        }
    }

    /// One-time pass: recompute the cached derived fields (distance, pace, best split,
    /// checkpoint) for every finished workout using the current trackpoint filter.
    ///
    /// History-list distance, the detail-view Avg Pace, the checkpoint badge and the
    /// "new best" highlight all read these cached columns rather than recomputing on
    /// display, so a filter change (e.g. GPS-drift removal) doesn't reach them until the
    /// values are rewritten. Gated by a kv flag so it runs once after the upgrade.
    /// `avg_bpm` and `started_at` are left untouched.
    func recomputeDerivedFieldsIfNeeded(
        flagKey: String = "recompute_drift_filter_v1",
        trackpointFilter: ([Trackpoint]) -> [Trackpoint]
    ) throws {
        guard try kvGet(flagKey) == nil else { return }

        let ids: [Int64] = try dbWriter.read { db in
            try Int64.fetchAll(db, sql:
                "SELECT id FROM workouts WHERE finished_at IS NOT NULL")
        }

        // Read + compute outside the write lock; collect small result structs only.
        var updates: [(Int64, DerivedFields)] = []
        for id in ids {
            let trackpoints = try getTrackpoints(id)
            let pulses = try getPulses(id)
            updates.append((id, Self.computeDerivedFields(
                trackpoints: trackpoints, pulses: pulses, trackpointFilter: trackpointFilter)))
        }

        try dbWriter.write { db in
            for (id, d) in updates {
                try db.execute(sql: """
                    UPDATE workouts
                    SET distance = ?, avg_sec_per_km = ?,
                        best_split_sec = ?, checkpoint_count = ?, checkpoint_pace_sec = ?
                    WHERE id = ?
                    """, arguments: [d.distance, d.avgSecPerKm, d.bestSplitSec,
                                     d.checkpointCount, d.checkpointPaceSec, id])
            }
        }

        try kvSet(flagKey, value: "done")
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
