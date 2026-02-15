import Foundation

extension AppDatabase {

    /// Insert sample workouts for testing. Clears any existing data first.
    func seedSampleData() throws {
        try dbWriter.write { db in
            try db.execute(sql: "DELETE FROM pulses")
            try db.execute(sql: "DELETE FROM trackpoints")
            try db.execute(sql: "DELETE FROM workouts")
        }

        // Helper: ISO string -> epoch
        let epoch = { (iso: String) -> TimeInterval in
            ISO8601DateFormatter().date(from: iso)!.timeIntervalSince1970
        }

        try insertSampleWorkout(
            startedAt: epoch("2026-02-10T07:30:00Z"),
            finishedAt: epoch("2026-02-10T08:02:30Z"),
            distance: 5200, avgSecPerKm: 375, avgBpm: 152,
            startLat: 51.5074, startLng: -0.1278,
            bearingDeg: 45, numPoints: 390, intervalSec: 5,
            baseBpm: 148)

        try insertSampleWorkout(
            startedAt: epoch("2026-02-13T17:15:00Z"),
            finishedAt: epoch("2026-02-13T17:35:00Z"),
            distance: 3100, avgSecPerKm: 387, avgBpm: 158,
            startLat: 51.5155, startLng: -0.1410,
            bearingDeg: 135, numPoints: 240, intervalSec: 5,
            baseBpm: 155)

        try insertSampleWorkout(
            startedAt: epoch("2026-02-14T06:00:00Z"),
            finishedAt: epoch("2026-02-14T06:55:00Z"),
            distance: 8400, avgSecPerKm: 393, avgBpm: 155,
            startLat: 51.5010, startLng: -0.1190,
            bearingDeg: 315, numPoints: 660, intervalSec: 5,
            baseBpm: 152)

        // 25km route — stress test for performance
        try insertSampleWorkout(
            startedAt: epoch("2026-02-08T05:30:00Z"),
            finishedAt: epoch("2026-02-08T08:00:00Z"),
            distance: 25000, avgSecPerKm: 360, avgBpm: 150,
            startLat: 51.4950, startLng: -0.1000,
            bearingDeg: 200, numPoints: 5000, intervalSec: 5,
            baseBpm: 145)
    }

    private func insertSampleWorkout(
        startedAt: TimeInterval, finishedAt: TimeInterval,
        distance: Double, avgSecPerKm: Double, avgBpm: Double,
        startLat: Double, startLng: Double,
        bearingDeg: Double, numPoints: Int, intervalSec: Int,
        baseBpm: Int
    ) throws {
        let workoutId = try dbWriter.write { db -> Int64 in
            try db.execute(sql: """
                INSERT INTO workouts (started_at, finished_at, distance, avg_sec_per_km, avg_bpm)
                VALUES (?, ?, ?, ?, ?)
                """, arguments: [startedAt, finishedAt, distance, avgSecPerKm, avgBpm])
            return db.lastInsertedRowID
        }

        let bearing = bearingDeg * .pi / 180
        var lat = startLat
        var lng = startLng
        let baseSpeed = 3.5

        try dbWriter.write { db in
            for i in 0..<numPoints {
                let speed = baseSpeed + Double.random(in: -0.5...0.5)
                let err = Double.random(in: 3...12)
                let t = startedAt + Double(i * intervalSec)

                try db.execute(sql: """
                    INSERT INTO trackpoints (workout_id, created_at, lat, lng, speed, err)
                    VALUES (?, ?, ?, ?, ?, ?)
                    """, arguments: [workoutId, t, lat, lng, speed, err])

                let distM = speed * Double(intervalSec)
                lat += (distM * cos(bearing)) / 111320
                lng += (distM * sin(bearing)) / (111320 * cos(lat * .pi / 180))
            }

            for i in 0..<(numPoints * intervalSec) {
                let bpm = baseBpm + Int.random(in: -10...15)
                let t = startedAt + Double(i)

                try db.execute(sql: """
                    INSERT INTO pulses (workout_id, created_at, bpm)
                    VALUES (?, ?, ?)
                    """, arguments: [workoutId, t, bpm])
            }
        }
    }
}
