import Foundation

struct KmSegment: Sendable {
    let paceSecPerKm: Double
    let km: Double
}

struct DayActivity: Sendable {
    let dayOfYear: Int
    let segments: [KmSegment]
    var totalKm: Double { segments.reduce(0) { $0 + $1.km } }
}

struct YearlyStats: Identifiable, Sendable {
    let year: Int
    let runKm: Double
    let walkKm: Double
    let avgRunPaceSecPerKm: Double?
    let dailyActivity: [DayActivity]

    var id: Int { year }
}

@MainActor
@Observable
final class YearlyStatsVM {
    private(set) var yearlyStats: [YearlyStats] = []
    private(set) var projected: YearlyStats?
    private(set) var maxDailyKm: Double = 0
    private(set) var isLoading = true

    private let db: AppDatabase

    nonisolated private static let runPaceThreshold: Double = 480

    init(db: AppDatabase = .shared) {
        self.db = db
    }

    func load() {
        isLoading = true
        let db = self.db

        Task.detached {
            let result = Self.compute(db: db)
            await MainActor.run { [result] in
                self.yearlyStats = result.stats
                self.projected = result.projected
                self.maxDailyKm = result.maxDailyKm
                self.isLoading = false
            }
        }
    }

    private struct ComputeResult: Sendable {
        let stats: [YearlyStats]
        let projected: YearlyStats?
        let maxDailyKm: Double
    }

    nonisolated private static func compute(db: AppDatabase) -> ComputeResult {
        guard let workouts = try? db.getWorkoutHistory() else {
            return ComputeResult(stats: [], projected: nil, maxDailyKm: 0)
        }

        let calendar = Calendar.current

        struct YearAccum {
            var runKm: Double = 0
            var walkKm: Double = 0
            var totalRunSeconds: Double = 0
            // dayOfYear -> [KmSegment]
            var days: [Int: [KmSegment]] = [:]
        }

        var yearData: [Int: YearAccum] = [:]

        for workout in workouts {
            let date = Date(timeIntervalSince1970: workout.startedAt)
            let year = calendar.component(.year, from: date)
            let dayOfYear = calendar.ordinality(of: .day, in: .year, for: date) ?? 1

            var entry = yearData[year, default: YearAccum()]

            let allTrackpoints = (try? db.getTrackpoints(workout.id!)) ?? []
            let trackpoints = TrackpointFilter.filterReliable(allTrackpoints)
            let splits = SplitCalc.computeKmSplits(trackpoints: trackpoints, pulses: [])
            var daySegments = entry.days[dayOfYear, default: []]

            for split in splits {
                daySegments.append(KmSegment(paceSecPerKm: split.seconds, km: 1))
                if split.seconds < runPaceThreshold {
                    entry.runKm += 1
                    entry.totalRunSeconds += split.seconds
                } else {
                    entry.walkKm += 1
                }
            }

            let workoutKm = (workout.distance ?? 0) / 1000
            let remainderKm = workoutKm - Double(splits.count)
            if remainderKm > 0.1, let pace = workout.avgSecPerKm, pace > 0 {
                daySegments.append(KmSegment(paceSecPerKm: pace, km: remainderKm))
                if pace < runPaceThreshold {
                    entry.runKm += remainderKm
                    entry.totalRunSeconds += pace * remainderKm
                } else {
                    entry.walkKm += remainderKm
                }
            }

            entry.days[dayOfYear] = daySegments
            yearData[year] = entry
        }

        var globalMaxDaily: Double = 0

        let stats: [YearlyStats] = yearData
            .map { year, data in
                let daily = data.days.map { day, segs in
                    DayActivity(dayOfYear: day, segments: segs)
                }.sorted { $0.dayOfYear < $1.dayOfYear }

                for d in daily {
                    globalMaxDaily = max(globalMaxDaily, d.totalKm)
                }

                return YearlyStats(
                    year: year,
                    runKm: data.runKm,
                    walkKm: data.walkKm,
                    avgRunPaceSecPerKm: data.runKm > 0 ? data.totalRunSeconds / data.runKm : nil,
                    dailyActivity: daily
                )
            }
            .sorted { $0.year > $1.year }

        let currentYear = calendar.component(.year, from: Date())
        var projected: YearlyStats? = nil
        if let currentStats = stats.first(where: { $0.year == currentYear }) {
            let dayOfYear = Double(calendar.ordinality(of: .day, in: .year, for: Date()) ?? 1)
            let daysInYear = Double(calendar.range(of: .day, in: .year, for: Date())?.count ?? 365)
            let fraction = dayOfYear / daysInYear

            if fraction > 0 {
                projected = YearlyStats(
                    year: currentYear,
                    runKm: currentStats.runKm / fraction,
                    walkKm: currentStats.walkKm / fraction,
                    avgRunPaceSecPerKm: currentStats.avgRunPaceSecPerKm,
                    dailyActivity: []
                )
            }
        }

        return ComputeResult(stats: stats, projected: projected, maxDailyKm: globalMaxDaily)
    }
}
