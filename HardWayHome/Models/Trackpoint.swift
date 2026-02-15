import Foundation
import GRDB

struct Trackpoint: Codable, FetchableRecord, PersistableRecord, Sendable {
    var id: Int64?
    var workoutId: Int64
    var createdAt: TimeInterval
    var lat: Double
    var lng: Double
    var speed: Double?
    var err: Double?

    static let databaseTableName = "trackpoints"

    enum Columns: String, ColumnExpression {
        case id, workoutId = "workout_id", createdAt = "created_at"
        case lat, lng, speed, err
    }

    enum CodingKeys: String, CodingKey {
        case id
        case workoutId = "workout_id"
        case createdAt = "created_at"
        case lat, lng, speed, err
    }
}
