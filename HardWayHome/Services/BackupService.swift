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
            of: ".sqlite.gz", with: ".sqlite")

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

    // MARK: - Compression (gzip for universal compatibility)
    //
    // Produces standard gzip files (RFC 1952) that any tool can open.
    // Also reads legacy raw-deflate .z files from older backups.

    nonisolated private static func compressFile(source: URL) -> URL? {
        let dest = source.appendingPathExtension("gz")
        guard let input = FileHandle(forReadingAtPath: source.path) else { return nil }
        defer { input.closeFile() }

        try? FileManager.default.removeItem(at: dest)
        FileManager.default.createFile(atPath: dest.path, contents: nil)
        guard let output = FileHandle(forWritingAtPath: dest.path) else { return nil }
        defer { output.closeFile() }

        // Gzip header: magic, method=deflate, flags=0, mtime=0, xfl=0, OS=Unix
        output.write(Data([0x1f, 0x8b, 0x08, 0x00, 0, 0, 0, 0, 0x00, 0x03]))

        // Raw-deflate the content using Apple Compression framework
        let bufferSize = 65_536
        let srcBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        let dstBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { srcBuffer.deallocate(); dstBuffer.deallocate() }

        var stream = compression_stream(
            dst_ptr: dstBuffer, dst_size: bufferSize,
            src_ptr: srcBuffer, src_size: 0, state: nil)
        guard compression_stream_init(
            &stream, COMPRESSION_STREAM_ENCODE, COMPRESSION_ZLIB
        ) == COMPRESSION_STATUS_OK else { return nil }
        defer { compression_stream_destroy(&stream) }

        var crc: UInt32 = 0
        var totalSize: UInt32 = 0
        var inputDone = false

        while true {
            if stream.src_size == 0 && !inputDone {
                let data = input.readData(ofLength: bufferSize)
                if data.isEmpty {
                    inputDone = true
                } else {
                    // Update CRC32 and size from uncompressed data
                    data.withUnsafeBytes { buf in
                        let bytes = buf.bindMemory(to: UInt8.self)
                        for i in 0..<bytes.count {
                            crc = Self.crc32Update(crc, byte: bytes[i])
                        }
                    }
                    totalSize &+= UInt32(data.count)
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
            if status == COMPRESSION_STATUS_ERROR { return nil }
        }

        // Gzip trailer: CRC32 + uncompressed size (both little-endian uint32)
        var trailer = Data(count: 8)
        trailer[0] = UInt8(crc & 0xff)
        trailer[1] = UInt8((crc >> 8) & 0xff)
        trailer[2] = UInt8((crc >> 16) & 0xff)
        trailer[3] = UInt8((crc >> 24) & 0xff)
        trailer[4] = UInt8(totalSize & 0xff)
        trailer[5] = UInt8((totalSize >> 8) & 0xff)
        trailer[6] = UInt8((totalSize >> 16) & 0xff)
        trailer[7] = UInt8((totalSize >> 24) & 0xff)
        output.write(trailer)

        return dest
    }

    nonisolated private static func decompressFile(
        source: URL, dest: URL
    ) -> Bool {
        // Check magic bytes to distinguish gzip from legacy raw deflate
        guard let header = FileHandle(forReadingAtPath: source.path) else { return false }
        let magic = header.readData(ofLength: 2)
        header.closeFile()

        let isGzip = magic.count >= 2 && magic[0] == 0x1f && magic[1] == 0x8b
        if isGzip {
            return gzipDecompressFile(source: source, dest: dest)
        }
        return streamDecompress(source: source, dest: dest)
    }

    /// Decompress a standard gzip file: skip header, raw-inflate, ignore trailer.
    nonisolated private static func gzipDecompressFile(source: URL, dest: URL) -> Bool {
        guard var data = try? Data(contentsOf: source), data.count >= 18 else { return false }

        // Parse gzip header (RFC 1952)
        var offset = 10 // skip fixed 10-byte header
        let flags = data[3]
        if flags & 0x04 != 0 { // FEXTRA
            guard offset + 2 <= data.count else { return false }
            let xlen = Int(data[offset]) | (Int(data[offset + 1]) << 8)
            offset += 2 + xlen
        }
        if flags & 0x08 != 0 { // FNAME
            while offset < data.count && data[offset] != 0 { offset += 1 }
            offset += 1
        }
        if flags & 0x10 != 0 { // FCOMMENT
            while offset < data.count && data[offset] != 0 { offset += 1 }
            offset += 1
        }
        if flags & 0x02 != 0 { offset += 2 } // FHCRC

        // Strip header and 8-byte trailer, decompress the raw deflate in the middle
        data = data.subdata(in: offset..<(data.count - 8))

        try? FileManager.default.removeItem(at: dest)
        FileManager.default.createFile(atPath: dest.path, contents: nil)
        guard let output = FileHandle(forWritingAtPath: dest.path) else { return false }
        defer { output.closeFile() }

        let bufferSize = 65_536
        let dstBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { dstBuffer.deallocate() }

        var stream = compression_stream(
            dst_ptr: dstBuffer, dst_size: bufferSize,
            src_ptr: UnsafePointer<UInt8>(bitPattern: 1)!, src_size: 0, state: nil)
        guard compression_stream_init(
            &stream, COMPRESSION_STREAM_DECODE, COMPRESSION_ZLIB
        ) == COMPRESSION_STATUS_OK else { return false }
        defer { compression_stream_destroy(&stream) }

        return data.withUnsafeBytes { rawBuf -> Bool in
            guard let base = rawBuf.baseAddress?.assumingMemoryBound(to: UInt8.self)
            else { return false }
            stream.src_ptr = base
            stream.src_size = data.count

            while true {
                stream.dst_ptr = dstBuffer
                stream.dst_size = bufferSize
                let status = compression_stream_process(
                    &stream, Int32(COMPRESSION_STREAM_FINALIZE.rawValue))
                let written = bufferSize - stream.dst_size
                if written > 0 {
                    output.write(Data(bytes: dstBuffer, count: written))
                }
                if status == COMPRESSION_STATUS_END { return true }
                if status == COMPRESSION_STATUS_ERROR { return false }
            }
        }
    }

    /// Decompress legacy raw deflate (Apple Compression COMPRESSION_ZLIB) files.
    nonisolated private static func streamDecompress(source: URL, dest: URL) -> Bool {
        guard let input = FileHandle(forReadingAtPath: source.path) else { return false }
        defer { input.closeFile() }

        try? FileManager.default.removeItem(at: dest)
        FileManager.default.createFile(atPath: dest.path, contents: nil)
        guard let output = FileHandle(forWritingAtPath: dest.path) else { return false }
        defer { output.closeFile() }

        let bufferSize = 65_536
        let srcBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        let dstBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { srcBuffer.deallocate(); dstBuffer.deallocate() }

        var stream = compression_stream(
            dst_ptr: dstBuffer, dst_size: bufferSize,
            src_ptr: srcBuffer, src_size: 0, state: nil)
        guard compression_stream_init(
            &stream, COMPRESSION_STREAM_DECODE, COMPRESSION_ZLIB
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
            if status == COMPRESSION_STATUS_END { return true }
            if status == COMPRESSION_STATUS_ERROR { return false }
        }
    }

    // MARK: - CRC32 (for gzip trailer)

    nonisolated(unsafe) private static let crc32Table: [UInt32] = {
        (0..<256).map { i -> UInt32 in
            var c = UInt32(i)
            for _ in 0..<8 {
                c = (c & 1 != 0) ? (0xedb88320 ^ (c >> 1)) : (c >> 1)
            }
            return c
        }
    }()

    nonisolated private static func crc32Update(_ crc: UInt32, byte: UInt8) -> UInt32 {
        let c = crc ^ 0xffffffff
        let idx = Int((c ^ UInt32(byte)) & 0xff)
        return crc32Table[idx] ^ (c >> 8) ^ 0xffffffff
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

        let localSize = fileSize(fileURL)

        var request = URLRequest(url: targetURL)
        request.httpMethod = "PUT"
        request.setValue(
            "application/octet-stream", forHTTPHeaderField: "Content-Type")

        if let auth = config.authHeader() {
            request.setValue(auth, forHTTPHeaderField: "Authorization")
            await onLog?("Auth: Basic")
        }

        await onLog?("Uploading \(formatBytes(localSize))...")

        let progressDelegate = UploadProgressDelegate(
            totalSize: localSize, onLog: onLog)

        do {
            let (_, response) = try await URLSession.shared.upload(
                for: request, fromFile: fileURL, delegate: progressDelegate)
            let statusCode =
                (response as? HTTPURLResponse)?.statusCode ?? 0
            await onLog?("Response: \(statusCode)")

            guard (200..<300).contains(statusCode) else {
                log.error("WebDAV upload failed: HTTP \(statusCode)")
                return false
            }

            // Verify remote file size matches local file
            let sizeOK = await verifyRemoteSize(
                targetURL: targetURL, config: config,
                expectedSize: localSize, onLog: onLog)
            if !sizeOK { return false }

            return true
        } catch {
            log.error("WebDAV upload error: \(error)")
            await onLog?("ERROR: \(error.localizedDescription)")
            return false
        }
    }

    nonisolated private static func verifyRemoteSize(
        targetURL: URL, config: WebDAVConfig, expectedSize: Int,
        onLog: (@Sendable (String) async -> Void)? = nil
    ) async -> Bool {
        var headReq = URLRequest(url: targetURL)
        headReq.httpMethod = "HEAD"
        if let auth = config.authHeader() {
            headReq.setValue(auth, forHTTPHeaderField: "Authorization")
        }
        do {
            let (_, headResponse) = try await URLSession.shared.data(
                for: headReq)
            let remoteSize = (headResponse as? HTTPURLResponse)?
                .value(forHTTPHeaderField: "Content-Length")
                .flatMap(Int.init) ?? -1
            if remoteSize == expectedSize {
                await onLog?(
                    "Verified: remote size matches (\(formatBytes(expectedSize)))")
                return true
            } else if remoteSize < 0 {
                await onLog?("Warning: server did not return Content-Length, skipping size check")
                return true
            } else {
                await onLog?(
                    "ERROR: Size mismatch — local \(formatBytes(expectedSize)) vs remote \(formatBytes(remoteSize))")
                log.error(
                    "Upload size mismatch: local \(expectedSize) vs remote \(remoteSize)")
                return false
            }
        } catch {
            await onLog?("Warning: could not verify remote size (\(error.localizedDescription))")
            return true
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

        // Decompress if the file is a compressed backup (.gz or legacy .z)
        let sqliteURL: URL
        let isCompressed = filename.hasSuffix(".gz") || filename.hasSuffix(".z")
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
        return "hardwayhome-\(formatter.string(from: Date())).sqlite.gz"
    }

    nonisolated private static func fileSize(_ url: URL) -> Int {
        (try? FileManager.default.attributesOfItem(
            atPath: url.path)[.size] as? Int) ?? 0
    }

    nonisolated fileprivate static func formatBytes(_ bytes: Int) -> String {
        if bytes < 1024 { return "\(bytes) B" }
        if bytes < 1_048_576 {
            return String(format: "%.1f KB", Double(bytes) / 1024)
        }
        return String(format: "%.1f MB", Double(bytes) / 1_048_576)
    }
}

// MARK: - Upload progress delegate

private final class UploadProgressDelegate: NSObject, URLSessionTaskDelegate,
    @unchecked Sendable
{
    let totalSize: Int
    let onLog: (@Sendable (String) async -> Void)?
    // Only mutated from the URLSession delegate queue (serial), so safe.
    private var lastReportedBucket = -1

    init(totalSize: Int,
         onLog: (@Sendable (String) async -> Void)?) {
        self.totalSize = totalSize
        self.onLog = onLog
    }

    func urlSession(
        _ session: URLSession, task: URLSessionTask,
        didSendBodyData bytesSent: Int64,
        totalBytesSent: Int64,
        totalBytesExpectedToSend: Int64
    ) {
        guard totalSize > 0 else { return }
        let pct = Int(totalBytesSent * 100 / Int64(totalSize))
        // Log every 25% to avoid spamming the log
        let bucket = pct / 25 * 25
        guard bucket > lastReportedBucket else { return }
        lastReportedBucket = bucket

        let sent = BackupService.formatBytes(Int(totalBytesSent))
        let total = BackupService.formatBytes(totalSize)
        let msg = "Uploading: \(sent) / \(total) (\(pct)%)"
        Task { await onLog?(msg) }
    }
}
