import Foundation
import GRDB

struct Pulse: Codable, FetchableRecord, PersistableRecord, Sendable {
    var id: Int64?
    var workoutId: Int64
    var createdAt: String
    var bpm: Int

    static let databaseTableName = "pulses"

    enum Columns: String, ColumnExpression {
        case id, workoutId = "workout_id", createdAt = "created_at", bpm
    }

    enum CodingKeys: String, CodingKey {
        case id
        case workoutId = "workout_id"
        case createdAt = "created_at"
        case bpm
    }
}
