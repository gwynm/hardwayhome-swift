import SwiftUI

struct WorkoutDetailView: View {
    let workoutId: Int64
    let onBack: () -> Void

    @State private var data: DetailData?
    @State private var mergeInfo: MergeInfo?
    @State private var showMergeAlert = false

    private let db: AppDatabase

    init(workoutId: Int64, onBack: @escaping () -> Void, db: AppDatabase = .shared) {
        self.workoutId = workoutId
        self.onBack = onBack
        self.db = db

        guard let workout = try? db.getWorkout(workoutId),
              workout.finishedAt != nil else {
            _data = State(initialValue: nil)
            return
        }

        let allTrackpoints = (try? db.getTrackpoints(workoutId)) ?? []
        let trackpoints = TrackpointFilter.filterReliable(allTrackpoints)
        let pulses = (try? db.getPulses(workoutId)) ?? []
        let distance = PaceCalc.trackpointDistance(trackpoints)
        let rawDistance = PaceCalc.trackpointDistance(allTrackpoints)
        let elapsedSeconds = max(0, workout.finishedAt! - workout.startedAt)
        let splits = SplitCalc.computeKmSplits(trackpoints: trackpoints, pulses: pulses)

        _data = State(initialValue: DetailData(
            workout: workout,
            trackpoints: trackpoints,
            pulses: pulses,
            distance: distance,
            rawDistance: rawDistance,
            elapsedSeconds: elapsedSeconds,
            splits: splits))

        // Check if mergeable with previous workout
        if let prev = try? db.getPreviousWorkout(workoutId),
           let prevId = prev.id,
           let firstTrackpoint = allTrackpoints.first,
           let lastPrevTrackpoint = (try? db.getTrackpoints(prevId))?.last {
            let gapSeconds = firstTrackpoint.createdAt - lastPrevTrackpoint.createdAt
            if gapSeconds >= 0, gapSeconds <= 600 {
                let gapMetres = Geo.haversineMetres(
                    lastPrevTrackpoint.lat, lastPrevTrackpoint.lng,
                    firstTrackpoint.lat, firstTrackpoint.lng)
                _mergeInfo = State(initialValue: MergeInfo(
                    previousWorkout: prev,
                    gapSeconds: gapSeconds,
                    gapMetres: gapMetres))
            }
        }
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

                    if let info = mergeInfo {
                        Button {
                            showMergeAlert = true
                        } label: {
                            Label("Merge into Previous Workout", systemImage: "arrow.triangle.merge")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundStyle(.orange)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(Color.orange.opacity(0.15), in: RoundedRectangle(cornerRadius: 10))
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 20)
                        .alert("Merge into Previous?", isPresented: $showMergeAlert) {
                            Button("Merge", role: .destructive) {
                                do {
                                    try db.mergeWorkout(workoutId, into: info.previousWorkout.id!,
                                                        trackpointFilter: TrackpointFilter.filterReliable)
                                } catch {
                                    // Merge failed — stay on page
                                    return
                                }
                                onBack()
                            }
                            Button("Cancel", role: .cancel) {}
                        } message: {
                            Text("Gap: \(Formatting.formatDuration(info.gapSeconds)) / \(Formatting.formatDistance(info.gapMetres))\n\nThis will combine both workouts and cannot be undone.")
                        }
                    }

                    // Debug: unfiltered GPS distance and how much the reliability/drift
                    // filter removed from the displayed figure.
                    Text("Raw \(Formatting.formatDistance(data.rawDistance)) · filter cut \(Formatting.formatDistance(data.rawDistance - data.distance))")
                        .font(.system(size: 12).monospacedDigit())
                        .foregroundStyle(Color(white: 0.4))
                        .padding(.top, 24)
                        .accessibilityIdentifier("rawDistanceDebug")
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
        let rawDistance: Double
        let elapsedSeconds: Double
        let splits: [KmSplit]
    }

    struct MergeInfo {
        let previousWorkout: Workout
        let gapSeconds: Double
        let gapMetres: Double
    }
}
