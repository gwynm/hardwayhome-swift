import Testing
@testable import HardWayHome

@Suite("Workout Stats VM")
struct WorkoutStatsVMTests {

    private func makeDB() throws -> AppDatabase {
        try AppDatabase.empty()
    }

    /// Points 0.001° of latitude apart (~111 m), 30s apart.
    private func trackpoint(_ i: Int, base: Double) -> Trackpoint {
        Trackpoint(workoutId: 1, createdAt: base + Double(i * 30),
                   lat: 51.5 + Double(i) * 0.001, lng: -0.1, speed: nil, err: 5)
    }

    @Test("Km beep does not re-fire when a reload shrinks the splits")
    @MainActor
    func beepMonotonicAcrossReload() throws {
        let db = try makeDB()
        let vm = WorkoutStatsVM(db: db)
        var beeps = 0
        vm.playBeep = { beeps += 1 }

        let base = epoch("2026-06-28T10:00:00Z")
        vm.observe(workoutId: 1, startedAt: base,
                   locationService: LocationService(db: db),
                   heartRateService: HeartRateService(db: db))

        // Cross the 1 km boundary: 10 points ≈ 1001 m.
        for i in 0..<10 { vm.onTrackpoint(trackpoint(i, base: base)) }
        #expect(vm.splits.count == 1)
        #expect(beeps == 1)

        // Retroactive cleanup: the DB has no trackpoints, so a reload drops the split
        // (as the drift filter would after removing phantom distance).
        vm.reloadFromDatabase()
        #expect(vm.splits.isEmpty)

        // Re-crossing the same boundary must stay silent...
        for i in 0..<10 { vm.onTrackpoint(trackpoint(i, base: base)) }
        #expect(vm.splits.count == 1)
        #expect(beeps == 1)

        // ...but a genuinely new km still beeps.
        for i in 10..<19 { vm.onTrackpoint(trackpoint(i, base: base)) }
        #expect(vm.splits.count == 2)
        #expect(beeps == 2)

        vm.stop()
    }
}
