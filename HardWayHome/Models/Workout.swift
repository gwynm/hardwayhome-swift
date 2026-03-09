import Foundation
import GRDB

struct Workout: Codable, FetchableRecord, PersistableRecord, Sendable {
    var id: Int64?
    var startedAt: TimeInterval
    var finishedAt: TimeInterval?
    var distance: Double?
    var avgSecPerKm: Double?
    var avgBpm: Double?
    var bestSplitSec: Double?

    static let databaseTableName = "workouts"

    enum Columns: String, ColumnExpression {
        case id, startedAt = "started_at", finishedAt = "finished_at"
        case distance, avgSecPerKm = "avg_sec_per_km", avgBpm = "avg_bpm"
        case bestSplitSec = "best_split_sec"
    }

    enum CodingKeys: String, CodingKey {
        case id
        case startedAt = "started_at"
        case finishedAt = "finished_at"
        case distance
        case avgSecPerKm = "avg_sec_per_km"
        case avgBpm = "avg_bpm"
        case bestSplitSec = "best_split_sec"
    }

    var isStationary: Bool {
        (distance ?? 0) < 100
    }
}
