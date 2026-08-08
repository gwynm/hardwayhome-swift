import Foundation
import GRDB

/// Central database access. Call `AppDatabase.shared` for the app's live database,
/// or `AppDatabase.empty()` for an in-memory database in tests.
final class AppDatabase: Sendable {
    let dbWriter: any DatabaseWriter

    init(_ dbWriter: any DatabaseWriter) throws {
        self.dbWriter = dbWriter
        let migrator = self.migrator

        #if DEBUG && targetEnvironment(simulator)
        // Auto-erase (enabled below) is for disposable dev databases only. If this
        // one holds real workouts — e.g. production data restored onto a simulator —
        // stop before GRDB wipes it. This runs before any UI exists, so a crash with
        // a clear message stands in for a confirmation dialog.
        if try dbWriter.read(migrator.hasSchemaChanges), Self.containsWorkouts(dbWriter) {
            fatalError("""
                Migration schema changed, but the database contains workouts — \
                refusing to auto-erase. Delete the app (or the database file) \
                manually if the data is disposable.
                """)
        }
        #endif

        try migrator.migrate(dbWriter)
    }

    private static func containsWorkouts(_ dbWriter: any DatabaseWriter) -> Bool {
        do {
            return try dbWriter.read { db in
                (try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM workouts") ?? 0) > 0
            }
        } catch {
            return false // no workouts table yet — fresh database
        }
    }

    private var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        // Never on a physical device: a schema-text mismatch (the live db was
        // created by an older migration lineage than a fresh one produces) once
        // made a Debug install silently erase all real workout data.
        #if DEBUG && targetEnvironment(simulator)
        migrator.eraseDatabaseOnSchemaChange = true
        #endif

        migrator.registerMigration("v3") { db in
            try db.execute(sql: """
                CREATE TABLE workouts (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    started_at REAL NOT NULL,
                    finished_at REAL,
                    distance REAL,
                    avg_sec_per_km REAL,
                    avg_bpm REAL
                );

                CREATE TABLE trackpoints (
                    id INTEGER PRIMARY KEY,
                    workout_id INTEGER NOT NULL REFERENCES workouts(id) ON DELETE CASCADE,
                    created_at REAL NOT NULL,
                    lat REAL NOT NULL,
                    lng REAL NOT NULL,
                    speed REAL,
                    err REAL
                );

                CREATE TABLE pulses (
                    id INTEGER PRIMARY KEY,
                    workout_id INTEGER NOT NULL REFERENCES workouts(id) ON DELETE CASCADE,
                    created_at REAL NOT NULL,
                    bpm INTEGER NOT NULL
                );

                CREATE TABLE kv (
                    key TEXT PRIMARY KEY,
                    value TEXT NOT NULL
                );

                CREATE INDEX idx_trackpoints_workout ON trackpoints(workout_id, created_at);
                CREATE INDEX idx_pulses_workout ON pulses(workout_id, created_at);
                """)
        }

        migrator.registerMigration("v4") { db in
            try db.alter(table: "workouts") { t in
                t.add(column: "strava_id", .integer)
            }
        }

        migrator.registerMigration("v5_fix_null_finished_at") { db in
            try db.execute(sql: """
                UPDATE workouts SET finished_at = started_at
                WHERE finished_at IS NULL AND strava_id IS NOT NULL
                """)
        }

        migrator.registerMigration("v6_best_split") { db in
            try db.alter(table: "workouts") { t in
                t.add(column: "best_split_sec", .real)
            }
        }

        migrator.registerMigration("v7_checkpoint") { db in
            try db.alter(table: "workouts") { t in
                t.add(column: "checkpoint_count", .integer)
                t.add(column: "checkpoint_pace_sec", .real)
            }
        }

        return migrator
    }

    // MARK: - Shared instance

    /// The app's on-disk database, created lazily.
    static let shared: AppDatabase = {
        do {
            let url = try FileManager.default
                .url(for: .applicationSupportDirectory, in: .userDomainMask,
                     appropriateFor: nil, create: true)
                .appendingPathComponent("hardwayhome.db")
            var config = Configuration()
            config.foreignKeysEnabled = true
            let dbQueue = try DatabaseQueue(path: url.path, configuration: config)
            return try AppDatabase(dbQueue)
        } catch {
            fatalError("Database setup failed: \(error)")
        }
    }()

    /// In-memory database for tests.
    static func empty() throws -> AppDatabase {
        var config = Configuration()
        config.foreignKeysEnabled = true
        let dbQueue = try DatabaseQueue(configuration: config)
        return try AppDatabase(dbQueue)
    }
}
