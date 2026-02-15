import Foundation

/// Formatting utilities for display strings and ISO date parsing.
enum Formatting {

    // MARK: - ISO 8601 parsing

    /// Shared ISO8601 formatter — nonisolated(unsafe) because ISO8601DateFormatter
    /// is thread-safe in practice but not marked Sendable by Apple.
    private nonisolated(unsafe) static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    /// Fallback without fractional seconds.
    private nonisolated(unsafe) static let isoFormatterNoFrac: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    /// Parse an ISO 8601 date string to Date.
    static func parseISO(_ string: String) -> Date? {
        isoFormatter.date(from: string) ?? isoFormatterNoFrac.date(from: string)
    }

    /// Format a Date as ISO 8601 string.
    static func toISO(_ date: Date) -> String {
        isoFormatter.string(from: date)
    }

    // MARK: - Display formatting

    /// Format seconds-per-km as "m:ss" pace string.
    /// Returns "--:--" if value is nil/non-finite/non-positive.
    static func formatPace(_ secPerKm: Double?) -> String {
        guard let s = secPerKm, s.isFinite, s > 0 else { return "--:--" }
        let minutes = Int(s) / 60
        let seconds = Int(s) % 60
        return "\(minutes):\(String(format: "%02d", seconds))"
    }

    /// Format distance in metres as "X.XX km".
    static func formatDistance(_ metres: Double?) -> String {
        guard let m = metres else { return "0.00 km" }
        return String(format: "%.2f km", m / 1000)
    }

    /// Format a duration in seconds as "H:MM:SS" or "M:SS".
    static func formatDuration(_ totalSeconds: Double) -> String {
        let t = max(0, Int(totalSeconds))
        let h = t / 3600
        let m = (t % 3600) / 60
        let s = t % 60
        if h > 0 {
            return "\(h):\(String(format: "%02d", m)):\(String(format: "%02d", s))"
        }
        return "\(m):\(String(format: "%02d", s))"
    }

    /// Format BPM as a string, or "--" if nil.
    static func formatBpm(_ bpm: Double?) -> String {
        guard let b = bpm else { return "--" }
        return "\(Int(b.rounded()))"
    }

    /// Format BPM (Int) as a string, or "--" if nil.
    static func formatBpm(_ bpm: Int?) -> String {
        guard let b = bpm else { return "--" }
        return "\(b)"
    }

    /// Format an ISO date string as a short date with time: "13 Feb 14:02".
    /// Includes year if not the current year.
    static func formatDate(_ isoString: String) -> String {
        guard let date = parseISO(isoString) else { return isoString }
        let cal = Calendar.current
        let months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun",
                      "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
        let day = cal.component(.day, from: date)
        let month = months[cal.component(.month, from: date) - 1]
        let hours = String(format: "%02d", cal.component(.hour, from: date))
        let minutes = String(format: "%02d", cal.component(.minute, from: date))

        if cal.component(.year, from: date) == cal.component(.year, from: Date()) {
            return "\(day) \(month) \(hours):\(minutes)"
        }
        return "\(day) \(month) \(cal.component(.year, from: date)) \(hours):\(minutes)"
    }
}
