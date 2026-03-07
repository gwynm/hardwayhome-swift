import Compression
import Foundation
import GRDB
import os

private let log = Logger(subsystem: "com.gwynmorfey.hardwayhome.native", category: "backup")
private let maxLocalBackupsLimit = 10

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
/// Heavy work (snapshot, compression, upload) runs off the main actor;
/// only `status` updates happen on main for SwiftUI observation.
@MainActor
@Observable
final class BackupService {

    private(set) var status: BackupStatus = .idle

    static let kvWebdavURL = "backup_webdav_url"
    static let kvWebdavUsername = "backup_webdav_username"
    static let kvWebdavPassword = "backup_webdav_password"

    private let db: AppDatabase

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
        let dbWriter = db.dbWriter
        let config = loadWebDAVConfig()

        status = .inProgress
        let result = await Task.detached(priority: .utility) {
            await BackupService.performBackup(dbWriter: dbWriter, config: config)
        }.value

        switch result {
        case .success: status = .success
        case .notConfigured: status = .notConfigured
        case .failed: status = .failed
        }
        return result
    }

    // MARK: - Backup with logging (settings screen)

    func backupWithLogs(url: String, username: String?, password: String?,
                        onLog: @escaping @MainActor (String) -> Void) async -> Bool {
        let dbWriter = db.dbWriter
        let trimmedURL = url.trimmingCharacters(in: .whitespacesAndNewlines)
        let config: WebDAVConfig? = trimmedURL.isEmpty ? nil : WebDAVConfig(
            baseURL: trimmedURL, username: username, password: password)

        let sendableLog: @Sendable (String) async -> Void = { msg in
            await MainActor.run { onLog(msg) }
        }

        status = .inProgress
        let result = await Task.detached(priority: .utility) {
            await BackupService.performBackup(
                dbWriter: dbWriter, config: config, onLog: sendableLog)
        }.value

        let success = result == .success
        status = success ? .success : .failed
        onLog(success ? "SUCCESS" : "FAILED")
        return success
    }

    // MARK: - Core backup logic (runs off main actor)

    nonisolated private static func performBackup(
        dbWriter: any DatabaseWriter,
        config: WebDAVConfig?,
        onLog: (@Sendable (String) async -> Void)? = nil
    ) async -> BackupResult {
        let compressedFilename = makeFilename()
        let sqliteFilename = compressedFilename.replacingOccurrences(
            of: ".sqlite.z", with: ".sqlite")

        await onLog?("Creating snapshot...")
        guard let snapshotURL = createSnapshot(
            dbWriter: dbWriter, filename: sqliteFilename
        ) else {
            await onLog?("ERROR: Failed to create snapshot")
            return .failed
        }
        let rawSize = fileSize(snapshotURL)
        await onLog?("Snapshot: \(formatBytes(rawSize))")

        await onLog?("Compressing...")
        guard let compressedURL = compressFile(source: snapshotURL) else {
            await onLog?("ERROR: Compression failed")
            cleanup(snapshotURL)
            return .failed
        }
        let compSize = fileSize(compressedURL)
        let ratio = rawSize > 0
            ? String(format: "%.1fx", Double(rawSize) / Double(max(1, compSize)))
            : "?"
        await onLog?("Compressed: \(formatBytes(rawSize)) → \(formatBytes(compSize)) (\(ratio))")
        cleanup(snapshotURL)

        localBackup(fileURL: compressedURL, filename: compressedFilename)
        await onLog?("Local backup OK")

        guard let config else {
            await onLog?("No WebDAV config, skipping upload")
            cleanup(compressedURL)
            return .notConfigured
        }

        await onLog?("PUT \(config.targetURL(filename: compressedFilename))")
        let success = await uploadToWebDAV(
            fileURL: compressedURL, filename: compressedFilename,
            config: config, onLog: onLog)
        cleanup(compressedURL)
        return success ? .success : .failed
    }

    // MARK: - Snapshot

    nonisolated private static func createSnapshot(
        dbWriter: any DatabaseWriter, filename: String
    ) -> URL? {
        let cacheDir = FileManager.default.urls(
            for: .cachesDirectory, in: .userDomainMask).first!
        let snapshotURL = cacheDir.appendingPathComponent(filename)
        try? FileManager.default.removeItem(at: snapshotURL)

        do {
            try dbWriter.writeWithoutTransaction { dbConn in
                try dbConn.execute(
                    sql: "VACUUM INTO ?", arguments: [snapshotURL.path])
            }
            return snapshotURL
        } catch {
            log.error("VACUUM INTO failed: \(error)")
            return nil
        }
    }

    // MARK: - Compression (streaming, handles large files without loading into memory)

    nonisolated private static func compressFile(source: URL) -> URL? {
        let dest = source.appendingPathExtension("z")
        guard streamProcess(
            source: source, dest: dest,
            operation: COMPRESSION_STREAM_ENCODE
        ) else { return nil }
        return dest
    }

    nonisolated private static func decompressFile(
        source: URL, dest: URL
    ) -> Bool {
        streamProcess(
            source: source, dest: dest,
            operation: COMPRESSION_STREAM_DECODE)
    }

    nonisolated private static func streamProcess(
        source: URL, dest: URL,
        operation: compression_stream_operation
    ) -> Bool {
        guard let input = FileHandle(forReadingAtPath: source.path)
        else { return false }
        defer { input.closeFile() }

        try? FileManager.default.removeItem(at: dest)
        FileManager.default.createFile(atPath: dest.path, contents: nil)
        guard let output = FileHandle(forWritingAtPath: dest.path)
        else { return false }
        defer { output.closeFile() }

        let bufferSize = 65_536
        let srcBuffer = UnsafeMutablePointer<UInt8>.allocate(
            capacity: bufferSize)
        let dstBuffer = UnsafeMutablePointer<UInt8>.allocate(
            capacity: bufferSize)
        defer { srcBuffer.deallocate(); dstBuffer.deallocate() }

        var stream = compression_stream(
            dst_ptr: dstBuffer, dst_size: bufferSize,
            src_ptr: srcBuffer, src_size: 0, state: nil)
        guard compression_stream_init(
            &stream, operation, COMPRESSION_ZLIB
        ) == COMPRESSION_STATUS_OK else { return false }
        defer { compression_stream_destroy(&stream) }

        var inputDone = false

        while true {
            if stream.src_size == 0 && !inputDone {
                let data = input.readData(ofLength: bufferSize)
                if data.isEmpty {
                    inputDone = true
                } else {
                    data.copyBytes(to: srcBuffer, count: data.count)
                    stream.src_ptr = UnsafePointer(srcBuffer)
                    stream.src_size = data.count
                }
            }

            stream.dst_ptr = dstBuffer
            stream.dst_size = bufferSize

            let flags: Int32 = inputDone
                ? Int32(COMPRESSION_STREAM_FINALIZE.rawValue) : 0
            let status = compression_stream_process(&stream, flags)

            let written = bufferSize - stream.dst_size
            if written > 0 {
                output.write(Data(bytes: dstBuffer, count: written))
            }

            if status == COMPRESSION_STATUS_END { break }
            if status == COMPRESSION_STATUS_ERROR {
                log.error("Compression stream error")
                return false
            }
        }

        return true
    }

    // MARK: - Local backup

    nonisolated private static func localBackup(
        fileURL: URL, filename: String
    ) {
        let documentsDir = FileManager.default.urls(
            for: .documentDirectory, in: .userDomainMask).first!
        let backupDir = documentsDir.appendingPathComponent("backups")

        do {
            try FileManager.default.createDirectory(
                at: backupDir, withIntermediateDirectories: true)
            let destURL = backupDir.appendingPathComponent(filename)
            try? FileManager.default.removeItem(at: destURL)
            try FileManager.default.copyItem(at: fileURL, to: destURL)
        } catch {
            log.error("Local backup failed: \(error)")
        }

        pruneLocalBackups(dir: backupDir)
    }

    nonisolated private static func pruneLocalBackups(dir: URL) {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: nil) else { return }

        let backups = contents
            .filter { $0.lastPathComponent.hasPrefix("hardwayhome-") }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }

        for old in backups.dropFirst(maxLocalBackupsLimit) {
            try? FileManager.default.removeItem(at: old)
        }
    }

    // MARK: - WebDAV

    private struct WebDAVConfig: Sendable {
        let baseURL: String
        let username: String?
        let password: String?

        func targetURL(filename: String) -> String {
            baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                + "/" + filename
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
        return WebDAVConfig(
            baseURL: urlString, username: username, password: password)
    }

    nonisolated private static func uploadToWebDAV(
        fileURL: URL, filename: String, config: WebDAVConfig,
        onLog: (@Sendable (String) async -> Void)? = nil
    ) async -> Bool {
        guard let targetURL = URL(
            string: config.targetURL(filename: filename)
        ) else {
            log.error("Invalid WebDAV URL: \(config.baseURL)")
            return false
        }

        var request = URLRequest(url: targetURL)
        request.httpMethod = "PUT"
        request.setValue(
            "application/octet-stream", forHTTPHeaderField: "Content-Type")

        if let auth = config.authHeader() {
            request.setValue(auth, forHTTPHeaderField: "Authorization")
            await onLog?("Auth: Basic")
        }

        do {
            let (_, response) = try await URLSession.shared.upload(
                for: request, fromFile: fileURL)
            let statusCode =
                (response as? HTTPURLResponse)?.statusCode ?? 0
            await onLog?("Response: \(statusCode)")

            guard (200..<300).contains(statusCode) else {
                log.error("WebDAV upload failed: HTTP \(statusCode)")
                return false
            }
            return true
        } catch {
            log.error("WebDAV upload error: \(error)")
            await onLog?("ERROR: \(error.localizedDescription)")
            return false
        }
    }

    // MARK: - Restore

    func restoreFromWebDAV(
        url: String, username: String?, password: String?,
        filename: String,
        onLog: @escaping @MainActor (String) -> Void
    ) async -> Bool {
        let config = WebDAVConfig(
            baseURL: url, username: username, password: password)
        let sourceURLString = config.targetURL(filename: filename)
        onLog("GET \(sourceURLString)")

        guard let remoteURL = URL(string: sourceURLString) else {
            onLog("ERROR: Invalid URL")
            return false
        }

        var request = URLRequest(url: remoteURL)
        request.httpMethod = "GET"
        if let auth = config.authHeader() {
            request.setValue(auth, forHTTPHeaderField: "Authorization")
        }

        let downloadedURL: URL
        do {
            let (tempURL, response) = try await URLSession.shared.download(
                for: request)
            let statusCode =
                (response as? HTTPURLResponse)?.statusCode ?? 0
            let size = Self.fileSize(tempURL)
            onLog("Response: \(statusCode) (\(Self.formatBytes(size)))")
            guard (200..<300).contains(statusCode) else {
                onLog("ERROR: HTTP \(statusCode)")
                return false
            }
            let cacheDir = FileManager.default.urls(
                for: .cachesDirectory, in: .userDomainMask).first!
            downloadedURL = cacheDir.appendingPathComponent(
                "restore-\(UUID().uuidString)")
            try? FileManager.default.removeItem(at: downloadedURL)
            try FileManager.default.moveItem(at: tempURL, to: downloadedURL)
        } catch {
            onLog("ERROR: \(error.localizedDescription)")
            return false
        }

        // Decompress if the file is a .z compressed backup
        let sqliteURL: URL
        let isCompressed = filename.hasSuffix(".z")
        if isCompressed {
            onLog("Decompressing...")
            let decompressedURL =
                downloadedURL.appendingPathExtension("sqlite")
            let ok = await Task.detached(priority: .utility) {
                BackupService.decompressFile(
                    source: downloadedURL, dest: decompressedURL)
            }.value
            Self.cleanup(downloadedURL)
            guard ok else {
                onLog("ERROR: Decompression failed")
                Self.cleanup(decompressedURL)
                return false
            }
            onLog(
                "Decompressed: \(Self.formatBytes(Self.fileSize(decompressedURL)))"
            )
            sqliteURL = decompressedURL
        } else {
            sqliteURL = downloadedURL
        }

        onLog("Validating database...")
        guard Self.validateDatabase(at: sqliteURL, onLog: onLog) else {
            Self.cleanup(sqliteURL)
            return false
        }

        guard let dbPath = db.databasePath else {
            onLog("ERROR: Cannot determine database path")
            Self.cleanup(sqliteURL)
            return false
        }
        let dbURL = URL(fileURLWithPath: dbPath)

        onLog("Replacing database...")
        do {
            let fm = FileManager.default
            let backupURL = dbURL.deletingLastPathComponent()
                .appendingPathComponent("hardwayhome-pre-restore.db")
            try? fm.removeItem(at: backupURL)
            try fm.copyItem(at: dbURL, to: backupURL)
            onLog("Pre-restore backup saved")

            try? fm.removeItem(
                at: URL(fileURLWithPath: dbPath + "-wal"))
            try? fm.removeItem(
                at: URL(fileURLWithPath: dbPath + "-shm"))
            try fm.removeItem(at: dbURL)
            try fm.moveItem(at: sqliteURL, to: dbURL)
            onLog(
                "Database replaced. Restart the app to use the new data."
            )
            return true
        } catch {
            onLog("ERROR: \(error.localizedDescription)")
            Self.cleanup(sqliteURL)
            return false
        }
    }

    nonisolated private static func validateDatabase(
        at url: URL, onLog: (String) -> Void
    ) -> Bool {
        guard FileManager.default.fileExists(atPath: url.path) else {
            onLog("ERROR: Downloaded file does not exist")
            return false
        }
        guard
            let size = try? FileManager.default.attributesOfItem(
                atPath: url.path)[.size] as? Int,
            size > 1024
        else {
            onLog("ERROR: File too small to be a valid database")
            return false
        }

        do {
            let testDb = try DatabaseQueue(path: url.path)
            let tables: [String] = try testDb.read { db in
                let rows = try Row.fetchAll(
                    db,
                    sql:
                        "SELECT name FROM sqlite_master WHERE type='table'"
                )
                return rows.map { $0["name"] as String }
            }
            let required = ["workouts", "trackpoints", "pulses"]
            for table in required {
                guard tables.contains(table) else {
                    onLog("ERROR: Missing table '\(table)'")
                    return false
                }
            }
            onLog(
                "Validation OK (tables: \(tables.joined(separator: ", ")))"
            )
            return true
        } catch {
            onLog(
                "ERROR: Not a valid SQLite database: \(error.localizedDescription)"
            )
            return false
        }
    }

    // MARK: - Helpers

    nonisolated private static func cleanup(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    nonisolated private static func makeFilename() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH-mm-ss"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return "hardwayhome-\(formatter.string(from: Date())).sqlite.z"
    }

    nonisolated private static func fileSize(_ url: URL) -> Int {
        (try? FileManager.default.attributesOfItem(
            atPath: url.path)[.size] as? Int) ?? 0
    }

    nonisolated private static func formatBytes(_ bytes: Int) -> String {
        if bytes < 1024 { return "\(bytes) B" }
        if bytes < 1_048_576 {
            return String(format: "%.1f KB", Double(bytes) / 1024)
        }
        return String(format: "%.1f MB", Double(bytes) / 1_048_576)
    }
}
