import Foundation

/// Formatting utilities for display strings.
enum Formatting {

    // MARK: - Epoch / display

    /// Format an epoch timestamp as a short date with time: "13 Feb 26 14:02".
    static func formatDate(_ epoch: TimeInterval) -> String {
        let date = Date(timeIntervalSince1970: epoch)
        let cal = Calendar.current
        let months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun",
                      "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
        let day = cal.component(.day, from: date)
        let month = months[cal.component(.month, from: date) - 1]
        let year = cal.component(.year, from: date) % 100
        let hours = String(format: "%02d", cal.component(.hour, from: date))
        let minutes = String(format: "%02d", cal.component(.minute, from: date))
        return "\(day) \(month) \(String(format: "%02d", year)) \(hours):\(minutes)"
    }

    // MARK: - Display formatting

    /// Format seconds-per-km as "m:ss" pace string.
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
}
