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

    /// Distance back to the start point, routed when possible.
    let returnRoute = ReturnRouteService()

    var returnDistance: Double? { returnRoute.estimate?.metres }
    var returnIsCrowFlies: Bool { returnRoute.estimate?.isCrowFlies ?? false }
    /// Seconds to get home at the current 1 km pace.
    var returnEtaSeconds: Double? {
        guard let metres = returnDistance, let pace = pace1000m else { return nil }
        return metres / 1000 * pace
    }

    private var timer: Timer?
    private var workoutId: Int64?
    private var startedAtEpoch: TimeInterval?
    private let db: AppDatabase

    // Incremental state
    private var allPulses: [Pulse] = []
    private var splitState = SplitCalc.SplitState()

    /// High-water mark of km splits already beeped for. `reloadFromDatabase` re-runs the
    /// full drift filter and can retroactively shrink `splits`; without this, re-crossing
    /// the same km boundary would beep a second time.
    private var beepedKmCount = 0

    /// Injectable for tests; production plays the km-split beep.
    var playBeep: () -> Void = { SoundService.shared.playBeep() }

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

        beepedKmCount = 0
        returnRoute.reset()
        loadInitialState(workoutId: workoutId)

        locationService.onTrackpointInserted = { [weak self] tp in
            self?.onTrackpoint(tp)
        }
        heartRateService.onPulseInserted = { [weak self] pulse in
            self?.onPulse(pulse)
        }

        startElapsedTimer()
    }

    /// Reload all stats from the database, catching up on any trackpoints/pulses
    /// that were inserted while the app was suspended.
    func reloadFromDatabase() {
        guard let workoutId else { return }
        loadInitialState(workoutId: workoutId)
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

        if let start = trackpoints.first, trackpoints.count >= 2 {
            returnRoute.noteLocation(startLat: start.lat, startLng: start.lng,
                                     currentLat: tp.lat, currentLng: tp.lng,
                                     now: tp.createdAt)
        }

        splitState.advance(newTrackpoint: tp, pulses: allPulses)
        splits = splitState.splits

        if splits.count > beepedKmCount {
            beepedKmCount = splits.count
            playBeep()
        }

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
            // Never lower the mark: a reload that filters points out must not re-arm the beep.
            beepedKmCount = max(beepedKmCount, splits.count)

            if let start = reliable.first, let last = reliable.last, reliable.count >= 2 {
                // Trackpoint time, not wall time — keeps the refresh gate in one
                // clock domain with onTrackpoint updates.
                returnRoute.noteLocation(startLat: start.lat, startLng: start.lng,
                                         currentLat: last.lat, currentLng: last.lng,
                                         now: last.createdAt)
            }

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
