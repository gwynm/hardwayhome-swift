import SwiftUI

struct WorkoutDetailView: View {
    let workoutId: Int64
    let onBack: () -> Void

    @State private var data: DetailData?

    init(workoutId: Int64, onBack: @escaping () -> Void, db: AppDatabase = .shared) {
        self.workoutId = workoutId
        self.onBack = onBack

        guard let workout = try? db.getWorkout(workoutId),
              workout.finishedAt != nil else {
            _data = State(initialValue: nil)
            return
        }

        let allTrackpoints = (try? db.getTrackpoints(workoutId)) ?? []
        let trackpoints = TrackpointFilter.filterReliable(allTrackpoints)
        let pulses = (try? db.getPulses(workoutId)) ?? []
        let distance = PaceCalc.trackpointDistance(trackpoints)
        let elapsedSeconds = max(0, workout.finishedAt! - workout.startedAt)
        let splits = SplitCalc.computeKmSplits(trackpoints: trackpoints, pulses: pulses)

        _data = State(initialValue: DetailData(
            workout: workout,
            trackpoints: trackpoints,
            pulses: pulses,
            distance: distance,
            elapsedSeconds: elapsedSeconds,
            splits: splits))
    }

    var body: some View {
        if let data {
            ScrollView {
                VStack(spacing: 0) {
                    // Header
                    HStack {
                        Button(action: onBack) {
                            HStack(spacing: 4) {
                                Image(systemName: "chevron.left")
                                Text("Back")
                            }
                            .font(.system(size: 17, weight: .medium))
                            .foregroundStyle(.blue)
                        }
                        Spacer()
                        Text(Formatting.formatDate(data.workout.startedAt))
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(.white)
                        Spacer()
                        Color.clear.frame(width: 60)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)

                    // Summary stats
                    VStack(spacing: 2) {
                        if data.workout.isStationary {
                            HStack(spacing: 2) {
                                StatCell(label: "Time", value: Formatting.formatDuration(data.elapsedSeconds))
                                StatCell(label: "Avg BPM", value: Formatting.formatBpm(data.workout.avgBpm))
                            }
                        } else {
                            HStack(spacing: 2) {
                                StatCell(label: "Distance", value: Formatting.formatDistance(data.distance))
                                StatCell(label: "Time", value: Formatting.formatDuration(data.elapsedSeconds))
                            }
                            HStack(spacing: 2) {
                                StatCell(label: "Avg Pace", value: Formatting.formatPace(data.workout.avgSecPerKm))
                                StatCell(label: "Avg BPM", value: Formatting.formatBpm(data.workout.avgBpm))
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)

                    if data.workout.isStationary {
                        HeartRateChartView(
                            pulses: data.pulses,
                            workoutStartedAt: data.workout.startedAt,
                            elapsedSeconds: data.elapsedSeconds)
                    } else {
                        KmSplitsTable(splits: data.splits)
                        RouteMapView(trackpoints: data.trackpoints)
                    }
                }
                .padding(.bottom, 40)
            }
        } else {
            VStack(spacing: 12) {
                Text("Workout not found")
                    .font(.system(size: 17))
                    .foregroundStyle(Color(white: 0.56))
                Button(action: onBack) {
                    Text("Back")
                        .foregroundStyle(.blue)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    struct DetailData {
        let workout: Workout
        let trackpoints: [Trackpoint]
        let pulses: [Pulse]
        let distance: Double
        let elapsedSeconds: Double
        let splits: [KmSplit]
    }
}
