import Foundation
import GRDB

/// Central database access. Call `AppDatabase.shared` for the app's live database,
/// or `AppDatabase.empty()` for an in-memory database in tests.
final class AppDatabase: Sendable {
    let dbWriter: any DatabaseWriter

    init(_ dbWriter: any DatabaseWriter) throws {
        self.dbWriter = dbWriter
        try migrator.migrate(dbWriter)
    }

    private var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        #if DEBUG
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
