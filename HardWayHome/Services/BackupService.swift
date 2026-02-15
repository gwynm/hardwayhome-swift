import Foundation

/// Backup status for UI display.
enum BackupStatus: Sendable {
    case notConfigured
    case idle
    case inProgress
    case success
    case failed
}

/// Result of a backup operation.
enum BackupResult: Sendable {
    case notConfigured
    case success
    case failed
}

/// Manages database backup — local file copies and optional WebDAV upload.
@MainActor
@Observable
final class BackupService {

    private(set) var status: BackupStatus = .idle

    // KV keys for WebDAV config
    static let kvWebdavURL = "backup_webdav_url"
    static let kvWebdavUsername = "backup_webdav_username"
    static let kvWebdavPassword = "backup_webdav_password"

    private let db: AppDatabase
    private static let maxLocalBackups = 10

    init(db: AppDatabase = .shared) {
        self.db = db
    }

    /// Initialize status from stored config on app launch.
    func initStatus() {
        let url = try? db.kvGet(Self.kvWebdavURL)
        status = (url?.isEmpty == false) ? .idle : .notConfigured
    }

    // MARK: - Backup

    /// Run a backup after finishing a workout. Non-interactive.
    @discardableResult
    func backupDatabase() async -> BackupResult {
        let timestamp = Self.timestampString()
        let filename = "hardwayhome-\(timestamp).sqlite"

        let snapshot = createSnapshot(filename: filename)
        guard let snapshotURL = snapshot.url else {
            print("[Backup] \(snapshot.error ?? "unknown error")")
            return .failed
        }

        // Always do local backup
        localBackup(snapshotURL: snapshotURL, filename: filename)

        // WebDAV if configured
        guard let urlString = try? db.kvGet(Self.kvWebdavURL),
              !urlString.isEmpty else {
            cleanup(snapshotURL)
            status = .notConfigured
            return .notConfigured
        }

        status = .inProgress

        do {
            try await webdavUpload(snapshotURL: snapshotURL, filename: filename,
                                   baseURL: urlString)
            cleanup(snapshotURL)
            status = .success
            return .success
        } catch {
            cleanup(snapshotURL)
            status = .failed
            return .failed
        }
    }

    /// Run a backup with detailed logging for the settings screen.
    func backupWithLogs(url: String, username: String?, password: String?,
                        onLog: @escaping @MainActor (String) -> Void) async -> Bool {
        let timestamp = Self.timestampString()
        let filename = "hardwayhome-\(timestamp).sqlite"

        onLog("Creating database snapshot (VACUUM INTO)...")
        let snapshot = createSnapshot(filename: filename)
        guard let snapshotURL = snapshot.url else {
            onLog("ERROR: \(snapshot.error ?? "Failed to create snapshot")")
            return false
        }
        onLog("Snapshot created: \(snapshotURL.path)")

        // Local backup
        onLog("Creating local backup...")
        localBackup(snapshotURL: snapshotURL, filename: filename)
        onLog("Local backup OK")

        let trimmedURL = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedURL.isEmpty else {
            onLog("No WebDAV URL provided, skipping remote backup.")
            cleanup(snapshotURL)
            return false
        }

        let targetURL = trimmedURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            + "/" + filename
        onLog("Target URL: \(targetURL)")

        do {
            let data = try Data(contentsOf: snapshotURL)
            onLog("File size: \(data.count) bytes")

            var request = URLRequest(url: URL(string: targetURL)!)
            request.httpMethod = "PUT"
            request.setValue("application/x-sqlite3", forHTTPHeaderField: "Content-Type")

            if let user = username, !user.isEmpty {
                let credentials = "\(user):\(password ?? "")"
                let encoded = Data(credentials.utf8).base64EncodedString()
                request.setValue("Basic \(encoded)", forHTTPHeaderField: "Authorization")
                onLog("Auth: Basic (username: \(user))")
            } else {
                onLog("Auth: none")
            }

            onLog("Sending PUT request...")
            let (_, response) = try await URLSession.shared.upload(for: request, from: data)

            let httpResponse = response as? HTTPURLResponse
            let statusCode = httpResponse?.statusCode ?? 0
            onLog("Response: \(statusCode)")

            cleanup(snapshotURL)

            if (200..<300).contains(statusCode) {
                onLog("SUCCESS")
                status = .success
                return true
            } else {
                onLog("FAILED")
                status = .failed
                return false
            }
        } catch {
            onLog("ERROR: \(error.localizedDescription)")
            cleanup(snapshotURL)
            status = .failed
            return false
        }
    }

    // MARK: - Snapshot

    /// Create a VACUUM INTO snapshot. Returns the file URL and nil error, or nil URL and error description.
    private func createSnapshot(filename: String) -> (url: URL?, error: String?) {
        guard let dbPath = db.databasePath else {
            return (nil, "databasePath is nil (in-memory database?)")
        }

        let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        let snapshotURL = cacheDir.appendingPathComponent(filename)

        // Remove previous snapshot with same name
        try? FileManager.default.removeItem(at: snapshotURL)

        do {
            // VACUUM INTO cannot run inside a transaction, so use
            // writeWithoutTransaction to get a bare connection.
            try db.dbWriter.writeWithoutTransaction { dbConn in
                try dbConn.execute(sql: "VACUUM INTO ?", arguments: [snapshotURL.path])
            }
            return (snapshotURL, nil)
        } catch {
            return (nil, "VACUUM INTO failed (dbPath=\(dbPath)): \(error)")
        }
    }

    // MARK: - Local backup

    private func localBackup(snapshotURL: URL, filename: String) {
        let documentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let backupDir = documentsDir.appendingPathComponent("backups")

        try? FileManager.default.createDirectory(at: backupDir,
                                                  withIntermediateDirectories: true)

        let destURL = backupDir.appendingPathComponent(filename)
        try? FileManager.default.copyItem(at: snapshotURL, to: destURL)

        // Prune old backups
        pruneLocalBackups(dir: backupDir)
    }

    private func pruneLocalBackups(dir: URL) {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: nil) else { return }

        let backups = contents
            .filter { $0.lastPathComponent.hasPrefix("hardwayhome-") && $0.pathExtension == "sqlite" }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }

        for old in backups.dropFirst(Self.maxLocalBackups) {
            try? FileManager.default.removeItem(at: old)
        }
    }

    // MARK: - WebDAV

    private func webdavUpload(snapshotURL: URL, filename: String, baseURL: String) async throws {
        let url = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let targetURL = URL(string: "\(url)/\(filename)")!

        let data = try Data(contentsOf: snapshotURL)

        var request = URLRequest(url: targetURL)
        request.httpMethod = "PUT"
        request.setValue("application/x-sqlite3", forHTTPHeaderField: "Content-Type")

        // Auth
        if let username = try? db.kvGet(Self.kvWebdavUsername), !username.isEmpty {
            let password = (try? db.kvGet(Self.kvWebdavPassword)) ?? ""
            let credentials = "\(username):\(password)"
            let encoded = Data(credentials.utf8).base64EncodedString()
            request.setValue("Basic \(encoded)", forHTTPHeaderField: "Authorization")
        }

        let (_, response) = try await URLSession.shared.upload(for: request, from: data)

        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }
    }

    // MARK: - Helpers

    private func cleanup(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    private static func timestampString() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH-mm-ss"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.string(from: Date())
    }
}
