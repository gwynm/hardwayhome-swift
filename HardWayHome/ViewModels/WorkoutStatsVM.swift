import Foundation
import GRDB
import Combine

/// Provides live workout stats via GRDB observation.
@MainActor
@Observable
final class WorkoutStatsVM {

    var distance: Double = 0
    var elapsedSeconds: Double = 0
    var pace100m: Double? = nil
    var pace1000m: Double? = nil
    var bpm5s: Double? = nil
    var bpm60s: Double? = nil
    var trackpoints: [Trackpoint] = []
    var splits: [KmSplit] = []

    private var cancellable: AnyCancellable?
    private var timer: Timer?
    private var workoutId: Int64?
    private var startedAtEpoch: TimeInterval?
    private let db: AppDatabase

    init(db: AppDatabase = .shared) {
        self.db = db
    }

    /// Start observing stats for a workout.
    func observe(workoutId: Int64, startedAt: TimeInterval) {
        self.workoutId = workoutId
        self.startedAtEpoch = startedAt
        startObservation(workoutId: workoutId)
        startElapsedTimer()
    }

    /// Stop observing.
    func stop() {
        cancellable?.cancel()
        cancellable = nil
        timer?.invalidate()
        timer = nil
        workoutId = nil
        startedAtEpoch = nil
    }

    private func startObservation(workoutId: Int64) {
        let observation = ValueObservation.tracking { db -> ([Trackpoint], [Pulse]) in
            let trackpoints = try Trackpoint
                .filter(Trackpoint.Columns.workoutId == workoutId)
                .order(Trackpoint.Columns.createdAt.asc)
                .fetchAll(db)
            let pulses = try Pulse
                .filter(Pulse.Columns.workoutId == workoutId)
                .order(Pulse.Columns.createdAt.asc)
                .fetchAll(db)
            return (trackpoints, pulses)
        }

        cancellable = observation
            .publisher(in: db.dbWriter, scheduling: .immediate)
            .sink(
                receiveCompletion: { _ in },
                receiveValue: { [weak self] (allTrackpoints, pulses) in
                    self?.computeStats(allTrackpoints: allTrackpoints, pulses: pulses)
                }
            )
    }

    private func startElapsedTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.updateElapsed()
            }
        }
    }

    private func updateElapsed() {
        guard let startedAtEpoch else { return }
        elapsedSeconds = max(0, Date().timeIntervalSince1970 - startedAtEpoch)
    }

    private func computeStats(allTrackpoints: [Trackpoint], pulses: [Pulse]) {
        let reliable = TrackpointFilter.filterReliable(allTrackpoints)
        trackpoints = reliable
        distance = PaceCalc.trackpointDistance(reliable)
        pace100m = PaceCalc.paceOverWindow(reliable, windowMetres: 100)
        pace1000m = PaceCalc.paceOverWindow(reliable, windowMetres: 1000)
        splits = SplitCalc.computeKmSplits(trackpoints: reliable, pulses: pulses)

        // BPM from recent pulses
        let now = Date().timeIntervalSince1970
        bpm5s = avgBpm(pulses: pulses, lastSeconds: 5, now: now)
        bpm60s = avgBpm(pulses: pulses, lastSeconds: 60, now: now)

        updateElapsed()
    }

    private func avgBpm(pulses: [Pulse], lastSeconds: Int, now: TimeInterval) -> Double? {
        let cutoff = now - Double(lastSeconds)
        var sum = 0.0
        var count = 0
        for p in pulses.reversed() {
            if p.createdAt < cutoff { break }
            sum += Double(p.bpm)
            count += 1
        }
        return count > 0 ? sum / Double(count) : nil
    }
}
