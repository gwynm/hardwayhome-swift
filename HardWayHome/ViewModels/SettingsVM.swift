import Foundation

/// View model for the Settings screen.
@MainActor
@Observable
final class SettingsVM {
    var url: String = ""
    var username: String = ""
    var password: String = ""
    var hasChanges: Bool = false
    var isRunning: Bool = false
    var logs: [String] = []

    private let db: AppDatabase
    private let backupService: BackupService

    init(db: AppDatabase = .shared, backupService: BackupService) {
        self.db = db
        self.backupService = backupService
    }

    func load() {
        url = (try? db.kvGet(BackupService.kvWebdavURL)) ?? ""
        username = (try? db.kvGet(BackupService.kvWebdavUsername)) ?? ""
        password = (try? db.kvGet(BackupService.kvWebdavPassword)) ?? ""
        hasChanges = false
    }

    func save() {
        try? db.kvSet(BackupService.kvWebdavURL, value: url.trimmingCharacters(in: .whitespaces))
        try? db.kvSet(BackupService.kvWebdavUsername, value: username.trimmingCharacters(in: .whitespaces))
        try? db.kvSet(BackupService.kvWebdavPassword, value: password)
        backupService.initStatus()
        hasChanges = false
    }

    func backupNow() async {
        save()
        logs = []
        isRunning = true

        _ = await backupService.backupWithLogs(
            url: url.trimmingCharacters(in: .whitespaces),
            username: username.trimmingCharacters(in: .whitespaces).isEmpty
                ? nil : username.trimmingCharacters(in: .whitespaces),
            password: password.isEmpty ? nil : password,
            onLog: { [weak self] line in
                self?.logs.append(line)
            }
        )

        isRunning = false
    }

    func generateSeedData() {
        try? db.seedSampleData()
    }

    func clearAllWorkoutData() {
        try? db.clearAllWorkoutData()
    }

    func clearSettings() {
        url = ""
        username = ""
        password = ""
        logs = []
        try? db.kvSet(BackupService.kvWebdavURL, value: "")
        try? db.kvSet(BackupService.kvWebdavUsername, value: "")
        try? db.kvSet(BackupService.kvWebdavPassword, value: "")
        backupService.initStatus()
        hasChanges = false
    }
}
