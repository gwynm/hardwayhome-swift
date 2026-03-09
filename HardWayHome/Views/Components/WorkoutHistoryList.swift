import SwiftUI

/// Scrollable list of past workouts.
struct WorkoutHistoryList: View {
    let workouts: [Workout]
    let onSelect: (Int64) -> Void

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
                    Text("DISTANCE")
                        .frame(width: 80, alignment: .trailing)
                    Text("AV PACE")
                        .frame(width: 62, alignment: .trailing)
                    Text("AV BPM")
                        .frame(width: 52, alignment: .trailing)
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
                                            .frame(width: 80, alignment: .trailing)
                                        Text("")
                                            .frame(width: 62, alignment: .trailing)
                                    } else {
                                        Text(Formatting.formatDistance(workout.distance))
                                            .frame(width: 80, alignment: .trailing)
                                        Text(Formatting.formatPace(workout.avgSecPerKm))
                                            .frame(width: 62, alignment: .trailing)
                                    }
                                    Text(Formatting.formatBpm(workout.avgBpm))
                                        .frame(width: 52, alignment: .trailing)
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
}
