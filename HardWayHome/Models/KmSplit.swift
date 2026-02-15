import Foundation

struct KmSplit: Sendable {
    let km: Int          // 1-indexed split number
    let seconds: Double  // elapsed time for this split
    let avgBpm: Double?  // average BPM during this split
}
