import Testing
import Foundation
@testable import HardWayHome

@Suite("Formatting")
struct FormatTests {

    // MARK: - Pace

    @Test("formatPace normal values")
    func paceNormal() {
        #expect(Formatting.formatPace(345) == "5:45")
        #expect(Formatting.formatPace(300) == "5:00")
        #expect(Formatting.formatPace(60) == "1:00")
        #expect(Formatting.formatPace(599) == "9:59")
    }

    @Test("formatPace nil/invalid")
    func paceInvalid() {
        #expect(Formatting.formatPace(nil) == "--:--")
        #expect(Formatting.formatPace(0) == "--:--")
        #expect(Formatting.formatPace(-1) == "--:--")
        #expect(Formatting.formatPace(.infinity) == "--:--")
        #expect(Formatting.formatPace(.nan) == "--:--")
    }

    // MARK: - Distance

    @Test("formatDistance normal values")
    func distanceNormal() {
        #expect(Formatting.formatDistance(5200) == "5.20 km")
        #expect(Formatting.formatDistance(0) == "0.00 km")
        #expect(Formatting.formatDistance(999) == "1.00 km")  // 0.999 rounds to 1.00
    }

    @Test("formatDistance nil")
    func distanceNil() {
        #expect(Formatting.formatDistance(nil) == "0.00 km")
    }

    // MARK: - Duration

    @Test("formatDuration under an hour")
    func durationShort() {
        #expect(Formatting.formatDuration(0) == "0:00")
        #expect(Formatting.formatDuration(61) == "1:01")
        #expect(Formatting.formatDuration(599) == "9:59")
    }

    @Test("formatDuration over an hour")
    func durationLong() {
        #expect(Formatting.formatDuration(3661) == "1:01:01")
        #expect(Formatting.formatDuration(7200) == "2:00:00")
    }

    @Test("formatDuration negative clamped to zero")
    func durationNegative() {
        #expect(Formatting.formatDuration(-10) == "0:00")
    }

    // MARK: - BPM

    @Test("formatBpm")
    func bpm() {
        #expect(Formatting.formatBpm(142.4) == "142")
        #expect(Formatting.formatBpm(142.6) == "143")
        #expect(Formatting.formatBpm(nil as Double?) == "--")
    }

    // MARK: - Date display

    @Test("formatDate current year omits year")
    func formatDateCurrentYear() {
        let epoch = Date().timeIntervalSince1970
        let result = Formatting.formatDate(epoch)
        #expect(!result.contains("202"))
    }
}
