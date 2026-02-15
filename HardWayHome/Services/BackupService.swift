import Foundation
import os

private let log = Logger(subsystem: "com.gwynmorfey.hardwayhome.native", category: "backup")

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

    // MARK: - Backup (non-interactive, after workout)

    @discardableResult
    func backupDatabase() async -> BackupResult {
        let filename = Self.makeFilename()

        guard let snapshotURL = createSnapshot(filename: filename) else {
            return .failed
        }

        localBackup(snapshotURL: snapshotURL, filename: filename)

        guard let config = loadWebDAVConfig() else {
            cleanup(snapshotURL)
            status = .notConfigured
            return .notConfigured
        }

        status = .inProgress
        let success = await uploadToWebDAV(snapshotURL: snapshotURL, filename: filename, config: config)
        cleanup(snapshotURL)
        status = success ? .success : .failed
        return success ? .success : .failed
    }

    // MARK: - Backup with logging (settings screen)

    func backupWithLogs(url: String, username: String?, password: String?,
                        onLog: @escaping @MainActor (String) -> Void) async -> Bool {
        let filename = Self.makeFilename()

        onLog("Creating database snapshot...")
        guard let snapshotURL = createSnapshot(filename: filename) else {
            onLog("ERROR: Failed to create snapshot")
            return false
        }
        onLog("Snapshot: \(snapshotURL.lastPathComponent)")

        onLog("Local backup...")
        localBackup(snapshotURL: snapshotURL, filename: filename)
        onLog("Local backup OK")

        let trimmedURL = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedURL.isEmpty else {
            onLog("No WebDAV URL, skipping remote backup.")
            cleanup(snapshotURL)
            return false
        }

        let config = WebDAVConfig(baseURL: trimmedURL, username: username, password: password)
        let targetURL = config.targetURL(filename: filename)
        onLog("PUT \(targetURL)")

        let success = await uploadToWebDAV(
            snapshotURL: snapshotURL, filename: filename, config: config,
            onLog: onLog)
        cleanup(snapshotURL)
        onLog(success ? "SUCCESS" : "FAILED")
        status = success ? .success : .failed
        return success
    }

    // MARK: - Snapshot

    private func createSnapshot(filename: String) -> URL? {
        guard let dbPath = db.databasePath else {
            log.error("Cannot create snapshot: database path is nil (in-memory?)")
            return nil
        }

        let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        let snapshotURL = cacheDir.appendingPathComponent(filename)
        try? FileManager.default.removeItem(at: snapshotURL)

        do {
            try db.dbWriter.writeWithoutTransaction { dbConn in
                try dbConn.execute(sql: "VACUUM INTO ?", arguments: [snapshotURL.path])
            }
            return snapshotURL
        } catch {
            log.error("VACUUM INTO failed (dbPath=\(dbPath)): \(error)")
            return nil
        }
    }

    // MARK: - Local backup

    private func localBackup(snapshotURL: URL, filename: String) {
        let documentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let backupDir = documentsDir.appendingPathComponent("backups")

        do {
            try FileManager.default.createDirectory(at: backupDir, withIntermediateDirectories: true)
            let destURL = backupDir.appendingPathComponent(filename)
            try FileManager.default.copyItem(at: snapshotURL, to: destURL)
        } catch {
            log.error("Local backup failed: \(error)")
        }

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

    // MARK: - WebDAV (shared logic)

    private struct WebDAVConfig {
        let baseURL: String
        let username: String?
        let password: String?

        func targetURL(filename: String) -> String {
            baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/" + filename
        }

        func authHeader() -> String? {
            guard let user = username, !user.isEmpty else { return nil }
            let credentials = "\(user):\(password ?? "")"
            return "Basic " + Data(credentials.utf8).base64EncodedString()
        }
    }

    private func loadWebDAVConfig() -> WebDAVConfig? {
        guard let urlString = try? db.kvGet(Self.kvWebdavURL),
              !urlString.isEmpty else { return nil }
        let username = try? db.kvGet(Self.kvWebdavUsername)
        let password = try? db.kvGet(Self.kvWebdavPassword)
        return WebDAVConfig(baseURL: urlString, username: username, password: password)
    }

    /// Upload snapshot file to WebDAV. Uses file-based upload to avoid loading into memory.
    private func uploadToWebDAV(
        snapshotURL: URL, filename: String, config: WebDAVConfig,
        onLog: ((String) -> Void)? = nil
    ) async -> Bool {
        guard let targetURL = URL(string: config.targetURL(filename: filename)) else {
            log.error("Invalid WebDAV URL: \(config.baseURL)")
            return false
        }

        var request = URLRequest(url: targetURL)
        request.httpMethod = "PUT"
        request.setValue("application/x-sqlite3", forHTTPHeaderField: "Content-Type")

        if let auth = config.authHeader() {
            request.setValue(auth, forHTTPHeaderField: "Authorization")
            onLog?("Auth: Basic")
        }

        do {
            let (_, response) = try await URLSession.shared.upload(for: request, fromFile: snapshotURL)
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            onLog?("Response: \(statusCode)")

            guard (200..<300).contains(statusCode) else {
                log.error("WebDAV upload failed: HTTP \(statusCode)")
                return false
            }
            return true
        } catch {
            log.error("WebDAV upload error: \(error)")
            onLog?("ERROR: \(error.localizedDescription)")
            return false
        }
    }

    // MARK: - Helpers

    private func cleanup(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    private static func makeFilename() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH-mm-ss"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return "hardwayhome-\(formatter.string(from: Date())).sqlite"
    }
}
