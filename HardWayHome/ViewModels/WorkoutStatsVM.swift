import Foundation
import os

private let log = Logger(subsystem: "com.gwynmorfey.hardwayhome.native", category: "stats")

/// Provides live workout stats via incremental updates from location/HR services.
///
/// On `observe()`, loads existing data from the DB (for app-restart mid-workout),
/// then switches to O(1)-per-update incremental computation driven by callbacks
/// from `LocationService` and `HeartRateService`.
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

    private var timer: Timer?
    private var workoutId: Int64?
    private var startedAtEpoch: TimeInterval?
    private let db: AppDatabase

    // Incremental state
    private var allPulses: [Pulse] = []
    private var splitState = SplitCalc.SplitState()

    // Service references for callback teardown
    private weak var locationService: LocationService?
    private weak var heartRateService: HeartRateService?

    init(db: AppDatabase = .shared) {
        self.db = db
    }

    // MARK: - Public API

    /// Start observing stats for a workout. Loads existing data from DB,
    /// then wires up incremental callbacks on the services.
    func observe(workoutId: Int64, startedAt: TimeInterval,
                 locationService: LocationService,
                 heartRateService: HeartRateService) {
        self.workoutId = workoutId
        self.startedAtEpoch = startedAt
        self.locationService = locationService
        self.heartRateService = heartRateService

        loadInitialState(workoutId: workoutId)

        locationService.onTrackpointInserted = { [weak self] tp in
            self?.onTrackpoint(tp)
        }
        heartRateService.onPulseInserted = { [weak self] pulse in
            self?.onPulse(pulse)
        }

        startElapsedTimer()
    }

    /// Stop observing and tear down callbacks.
    func stop() {
        locationService?.onTrackpointInserted = nil
        heartRateService?.onPulseInserted = nil
        locationService = nil
        heartRateService = nil
        timer?.invalidate()
        timer = nil
        workoutId = nil
        startedAtEpoch = nil
    }

    // MARK: - Incremental updates

    /// Called for each new trackpoint inserted by LocationService.
    func onTrackpoint(_ tp: Trackpoint) {
        guard TrackpointFilter.isReliable(tp, after: trackpoints.last) else { return }

        if let prev = trackpoints.last {
            distance += Geo.haversineMetres(prev.lat, prev.lng, tp.lat, tp.lng)
        }

        trackpoints.append(tp)

        pace100m = PaceCalc.paceOverWindow(trackpoints, windowMetres: 100)
        pace1000m = PaceCalc.paceOverWindow(trackpoints, windowMetres: 1000)

        splitState.advance(newTrackpoint: tp, pulses: allPulses)
        splits = splitState.splits

        updateElapsed()
    }

    /// Called for each new pulse inserted by HeartRateService.
    func onPulse(_ pulse: Pulse) {
        allPulses.append(pulse)
        let now = Date().timeIntervalSince1970
        bpm5s = avgBpm(lastSeconds: 5, now: now)
        bpm60s = avgBpm(lastSeconds: 60, now: now)
    }

    // MARK: - Initial load (app restart mid-workout)

    private func loadInitialState(workoutId: Int64) {
        do {
            let allTrackpoints = try db.getTrackpoints(workoutId)
            allPulses = try db.getPulses(workoutId)

            let reliable = TrackpointFilter.filterReliable(allTrackpoints)
            trackpoints = reliable
            distance = PaceCalc.trackpointDistance(reliable)
            pace100m = PaceCalc.paceOverWindow(reliable, windowMetres: 100)
            pace1000m = PaceCalc.paceOverWindow(reliable, windowMetres: 1000)

            splitState = SplitCalc.SplitState()
            for tp in reliable {
                splitState.advance(newTrackpoint: tp, pulses: allPulses)
            }
            splits = splitState.splits

            let now = Date().timeIntervalSince1970
            bpm5s = avgBpm(lastSeconds: 5, now: now)
            bpm60s = avgBpm(lastSeconds: 60, now: now)
        } catch {
            log.error("Failed to load initial workout state: \(error)")
        }

        updateElapsed()
    }

    // MARK: - Elapsed timer

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

    // MARK: - BPM

    private func avgBpm(lastSeconds: Int, now: TimeInterval) -> Double? {
        let cutoff = now - Double(lastSeconds)
        var sum = 0.0
        var count = 0
        for p in allPulses.reversed() {
            if p.createdAt < cutoff { break }
            sum += Double(p.bpm)
            count += 1
        }
        return count > 0 ? sum / Double(count) : nil
    }
}
