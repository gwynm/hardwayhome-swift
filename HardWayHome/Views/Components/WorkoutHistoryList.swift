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
                        .frame(width: 90, alignment: .trailing)
                    Text("AV PACE")
                        .frame(width: 70, alignment: .trailing)
                    Text("AV BPM")
                        .frame(width: 60, alignment: .trailing)
                }
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color(white: 0.56))
                .tracking(0.5)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .overlay(alignment: .bottom) {
                    Divider().background(Color(white: 0.22))
                }

                // Rows
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(workouts, id: \.id) { workout in
                            Button(action: { onSelect(workout.id!) }) {
                                HStack {
                                    Text(Formatting.formatDate(workout.startedAt))
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    Text(Formatting.formatDistance(workout.distance))
                                        .frame(width: 90, alignment: .trailing)
                                    Text(Formatting.formatPace(workout.avgSecPerKm))
                                        .frame(width: 70, alignment: .trailing)
                                    Text(Formatting.formatBpm(workout.avgBpm))
                                        .frame(width: 60, alignment: .trailing)
                                }
                                .font(.system(size: 15).monospacedDigit())
                                .foregroundStyle(.white)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                                .overlay(alignment: .bottom) {
                                    Divider().background(Color(white: 0.17))
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
