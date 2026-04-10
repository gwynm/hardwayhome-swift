import SwiftUI

/// Scrollable list of past workouts.
struct WorkoutHistoryList: View {
    let workouts: [Workout]
    let onSelect: (Int64) -> Void

    /// Set of workout IDs whose checkpoint was a new best at the time.
    private var newBestIds: Set<Int64>

    init(workouts: [Workout], onSelect: @escaping (Int64) -> Void) {
        self.workouts = workouts
        self.onSelect = onSelect
        self.newBestIds = Self.computeNewBests(workouts)
    }

    var body: some View {
        if workouts.isEmpty {
            VStack {
                Spacer()
                Text("No workouts yet")
                    .font(.system(size: 17))
                    .foregroundStyle(Color(white: 0.56))
                Spacer()
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 60)
        } else {
            VStack(spacing: 0) {
                // Header
                HStack {
                    Text("DATE")
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text("DIST")
                        .frame(width: 70, alignment: .trailing)
                    Text("CHECKPOINT")
                        .frame(width: 100, alignment: .trailing)
                }
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color(white: 0.56))
                .tracking(0.5)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(Color(white: 0.22)).frame(height: 1.0 / UIScreen.main.scale)
                }

                // Rows
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(workouts, id: \.id) { workout in
                            Button(action: { onSelect(workout.id!) }) {
                                HStack {
                                    Text(Formatting.formatDate(workout.startedAt))
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    if workout.isStationary {
                                        Text(Formatting.formatDuration(
                                            (workout.finishedAt ?? workout.startedAt) - workout.startedAt))
                                            .frame(width: 70, alignment: .trailing)
                                    } else {
                                        Text(Formatting.formatDistance(workout.distance))
                                            .frame(width: 70, alignment: .trailing)
                                    }
                                    let isNewBest = newBestIds.contains(workout.id ?? -1)
                                    Text(Formatting.formatCheckpoint(
                                        count: workout.checkpointCount,
                                        paceSec: workout.checkpointPaceSec))
                                        .frame(width: 100, alignment: .trailing)
                                        .foregroundStyle(isNewBest ? .green : rowColor(for: workout))
                                        .fontWeight(isNewBest ? .bold : .regular)
                                }
                                .font(.system(size: 15).monospacedDigit())
                                .foregroundStyle(rowColor(for: workout))
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                                .overlay(alignment: .bottom) {
                                    Rectangle().fill(Color(white: 0.17)).frame(height: 1.0 / UIScreen.main.scale)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private func rowColor(for workout: Workout) -> Color {
        if workout.isStationary {
            return Color(red: 0.68, green: 0.85, blue: 1.0)
        }
        if let best = workout.bestSplitSec, best < 480 {
            return Color(red: 1.0, green: 0.85, blue: 0.3)
        }
        return .white
    }

    /// Determine which workouts had a checkpoint that was a new best at the time.
    /// Workouts are sorted newest-first; we process oldest-first to track the running best.
    private static func computeNewBests(_ workouts: [Workout]) -> Set<Int64> {
        var bestPace: Double? = nil
        var bestCount: Int = 0
        var result = Set<Int64>()

        for workout in workouts.reversed() {
            guard let pace = workout.checkpointPaceSec,
                  let count = workout.checkpointCount else { continue }
            let isBetter: Bool
            if let bp = bestPace {
                isBetter = pace < bp || (pace == bp && count > bestCount)
            } else {
                isBetter = true
            }
            if isBetter {
                bestPace = pace
                bestCount = count
                if let id = workout.id { result.insert(id) }
            }
        }
        return result
    }
}
