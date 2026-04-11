import Testing
@testable import HardWayHome

@MainActor
final class MockWatchdog: Watchdog {
    var armCount = 0
    var disarmCount = 0
    var permissionRequested = false

    func requestPermission() async {
        permissionRequested = true
    }

    func arm() {
        armCount += 1
    }

    func disarm() {
        disarmCount += 1
    }
}

@Suite("Watchdog lifecycle")
struct WatchdogTests {

    private func makeDB() throws -> AppDatabase {
        try AppDatabase.empty()
    }

    @Test("start arms the watchdog")
    @MainActor func startArms() throws {
        let db = try makeDB()
        let watchdog = MockWatchdog()
        let vm = WorkoutRecordingVM(db: db, watchdog: watchdog)

        vm.start()

        #expect(vm.activeWorkout != nil)
        #expect(watchdog.armCount == 1)
    }

    @Test("finish disarms the watchdog")
    @MainActor func finishDisarms() throws {
        let db = try makeDB()
        let watchdog = MockWatchdog()
        let vm = WorkoutRecordingVM(db: db, watchdog: watchdog)

        vm.start()
        vm.finish()

        #expect(watchdog.disarmCount == 1)
    }

    @Test("discard disarms the watchdog")
    @MainActor func discardDisarms() throws {
        let db = try makeDB()
        let watchdog = MockWatchdog()
        let vm = WorkoutRecordingVM(db: db, watchdog: watchdog)

        vm.start()
        vm.discard()

        #expect(watchdog.disarmCount == 1)
    }

    @Test("recovery arms the watchdog")
    @MainActor func recoveryArms() throws {
        let db = try makeDB()
        _ = try db.startWorkout()

        let watchdog = MockWatchdog()
        let vm = WorkoutRecordingVM(db: db, watchdog: watchdog)

        vm.checkForRecovery()

        #expect(vm.activeWorkout != nil)
        #expect(watchdog.armCount == 1)
    }

    @Test("recovery then finish: arm then disarm")
    @MainActor func recoveryThenFinish() throws {
        let db = try makeDB()
        _ = try db.startWorkout()

        let watchdog = MockWatchdog()
        let vm = WorkoutRecordingVM(db: db, watchdog: watchdog)

        vm.checkForRecovery()
        #expect(watchdog.armCount == 1)

        vm.finish()
        #expect(watchdog.disarmCount == 1)
    }

    @Test("no recovery when DB is empty does not arm")
    @MainActor func noRecoveryNoArm() throws {
        let db = try makeDB()
        let watchdog = MockWatchdog()
        let vm = WorkoutRecordingVM(db: db, watchdog: watchdog)

        vm.checkForRecovery()

        #expect(watchdog.armCount == 0)
    }
}
