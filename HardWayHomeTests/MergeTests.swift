import Foundation
import Testing
@testable import HardWayHome

@Suite("Workout Merge")
struct MergeTests {

    private func makeDB() throws -> AppDatabase {
        try AppDatabase.empty()
    }

    // Helper: create a finished workout with trackpoints and pulses
    private func createFinishedWorkout(
        db: AppDatabase,
        startedAt: TimeInterval,
        finishedAt: TimeInterval,
        trackpoints: [(TimeInterval, Double, Double)],
        pulses: [(TimeInterval, Int)] = []
    ) throws -> Int64 {
        let id = try db.dbWriter.write { conn -> Int64 in
            var w = Workout(startedAt: startedAt, finishedAt: finishedAt)
            try w.insert(conn)
            return conn.lastInsertedRowID
        }
        for (t, lat, lng) in trackpoints {
            try db.dbWriter.write { conn in
                try Trackpoint(workoutId: id, createdAt: t, lat: lat, lng: lng, speed: 3.0, err: 5.0)
                    .insert(conn)
            }
        }
        for (t, bpm) in pulses {
            try db.dbWriter.write { conn in
                try Pulse(workoutId: id, createdAt: t, bpm: bpm).insert(conn)
            }
        }
        return id
    }

    @Test("getPreviousWorkout returns the workout before the given one")
    func previousWorkoutFound() throws {
        let db = try makeDB()
        let t0 = epoch("2026-04-10T08:00:00Z")
        let prevId = try createFinishedWorkout(db: db, startedAt: t0, finishedAt: t0 + 1800,
            trackpoints: [(t0 + 10, 51.5, -0.1), (t0 + 1800, 51.51, -0.1)])
        let currentId = try createFinishedWorkout(db: db, startedAt: t0 + 2000, finishedAt: t0 + 3800,
            trackpoints: [(t0 + 2010, 51.51, -0.1), (t0 + 3800, 51.52, -0.1)])

        let prev = try db.getPreviousWorkout(currentId)
        #expect(prev?.id == prevId)
    }

    @Test("getPreviousWorkout returns nil when no previous workout exists")
    func previousWorkoutNil() throws {
        let db = try makeDB()
        let t0 = epoch("2026-04-10T08:00:00Z")
        let id = try createFinishedWorkout(db: db, startedAt: t0, finishedAt: t0 + 1800,
            trackpoints: [(t0 + 10, 51.5, -0.1)])

        let prev = try db.getPreviousWorkout(id)
        #expect(prev == nil)
    }

    @Test("mergeWorkout combines trackpoints and pulses")
    func mergeMovesData() throws {
        let db = try makeDB()
        let t0 = epoch("2026-04-10T08:00:00Z")
        let prevId = try createFinishedWorkout(db: db, startedAt: t0, finishedAt: t0 + 1800,
            trackpoints: [(t0 + 10, 51.5, -0.1), (t0 + 1800, 51.505, -0.1)],
            pulses: [(t0 + 10, 140), (t0 + 900, 150)])
        let srcId = try createFinishedWorkout(db: db, startedAt: t0 + 2000, finishedAt: t0 + 3800,
            trackpoints: [(t0 + 2010, 51.505, -0.1), (t0 + 3800, 51.51, -0.1)],
            pulses: [(t0 + 2010, 155), (t0 + 3000, 160)])

        try db.mergeWorkout(srcId, into: prevId, trackpointFilter: { $0 })

        let trackpoints = try db.getTrackpoints(prevId)
        #expect(trackpoints.count == 4)

        let pulses = try db.getPulses(prevId)
        #expect(pulses.count == 4)

        // Source workout should be deleted
        let srcWorkout = try db.getWorkout(srcId)
        #expect(srcWorkout == nil)
    }

    @Test("mergeWorkout recalculates cache fields")
    func mergeRecalculates() throws {
        let db = try makeDB()
        let t0 = epoch("2026-04-10T08:00:00Z")
        let prevId = try createFinishedWorkout(db: db, startedAt: t0, finishedAt: t0 + 1800,
            trackpoints: [(t0 + 10, 51.5, -0.1), (t0 + 1800, 51.505, -0.1)],
            pulses: [(t0 + 10, 140)])
        let srcId = try createFinishedWorkout(db: db, startedAt: t0 + 2000, finishedAt: t0 + 3800,
            trackpoints: [(t0 + 2010, 51.505, -0.1), (t0 + 3800, 51.51, -0.1)],
            pulses: [(t0 + 2010, 160)])

        try db.mergeWorkout(srcId, into: prevId, trackpointFilter: { $0 })

        let merged = try db.getWorkout(prevId)!
        #expect(merged.distance != nil)
        #expect(merged.distance! > 0)
        #expect(merged.avgBpm != nil)
        // avgBpm should be average of 140 and 160 = 150
        #expect(merged.avgBpm! == 150.0)
        #expect(merged.avgSecPerKm != nil)
    }

    @Test("mergeWorkout updates finished_at to latest data point")
    func mergeUpdatesFinishedAt() throws {
        let db = try makeDB()
        let t0 = epoch("2026-04-10T08:00:00Z")
        let prevId = try createFinishedWorkout(db: db, startedAt: t0, finishedAt: t0 + 1800,
            trackpoints: [(t0 + 10, 51.5, -0.1), (t0 + 1800, 51.505, -0.1)])
        let srcId = try createFinishedWorkout(db: db, startedAt: t0 + 2000, finishedAt: t0 + 3800,
            trackpoints: [(t0 + 2010, 51.505, -0.1), (t0 + 3800, 51.51, -0.1)])

        try db.mergeWorkout(srcId, into: prevId, trackpointFilter: { $0 })

        let merged = try db.getWorkout(prevId)!
        // finished_at should be the last trackpoint time from the source workout
        #expect(merged.finishedAt == t0 + 3800)
    }

    @Test("Source trackpoints with no data still works")
    func mergeEmptySource() throws {
        let db = try makeDB()
        let t0 = epoch("2026-04-10T08:00:00Z")
        let prevId = try createFinishedWorkout(db: db, startedAt: t0, finishedAt: t0 + 1800,
            trackpoints: [(t0 + 10, 51.5, -0.1)])
        let srcId = try createFinishedWorkout(db: db, startedAt: t0 + 2000, finishedAt: t0 + 3800,
            trackpoints: [])

        try db.mergeWorkout(srcId, into: prevId, trackpointFilter: { $0 })

        let trackpoints = try db.getTrackpoints(prevId)
        #expect(trackpoints.count == 1)
        #expect(try db.getWorkout(srcId) == nil)
    }
}
