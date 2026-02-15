import Foundation

/// Convert ISO 8601 string to epoch seconds for test convenience.
func epoch(_ iso: String) -> TimeInterval {
    ISO8601DateFormatter().date(from: iso)!.timeIntervalSince1970
}
