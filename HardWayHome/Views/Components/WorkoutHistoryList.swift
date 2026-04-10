import SwiftUI

/// Scrollable list of past workouts, with rest-day placeholders after 1 Jan 2026.
struct WorkoutHistoryList: View {
    let workouts: [Workout]
    let onSelect: (Int64) -> Void

    private var newBestIds: Set<Int64>
    private var rows: [Row]

    private enum Row: Identifiable {
        case workout(Workout)
        case restDay(TimeInterval) // midnight epoch for that date

        var id: String {
            switch self {
            case .workout(let w): "w\(w.id ?? 0)"
            case .restDay(let t): "r\(Int(t))"
            }
        }
    }

    init(workouts: [Workout], onSelect: @escaping (Int64) -> Void) {
        self.workouts = workouts
        self.onSelect = onSelect
        self.newBestIds = Self.computeNewBests(workouts)
        self.rows = Self.buildRows(workouts)
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
                        ForEach(rows) { row in
                            switch row {
                            case .workout(let workout):
                                Button(action: { onSelect(workout.id!) }) {
                                    workoutRow(workout)
                                }
                            case .restDay(let epoch):
                                restDayRow(epoch)
                            }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func workoutRow(_ workout: Workout) -> some View {
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

    @ViewBuilder
    private func restDayRow(_ epoch: TimeInterval) -> some View {
        HStack {
            Text(Formatting.formatDate(epoch))
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("0.00 km")
                .frame(width: 70, alignment: .trailing)
            Text("--")
                .frame(width: 100, alignment: .trailing)
        }
        .font(.system(size: 15).monospacedDigit())
        .foregroundStyle(Color(white: 0.3))
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color(white: 0.17)).frame(height: 1.0 / UIScreen.main.scale)
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

    /// Build the row list: workouts interleaved with rest-day placeholders for dates after 1 Jan 2026.
    /// Workouts are newest-first; rest days fill gaps between workout dates down to the cutoff.
    private static func buildRows(_ workouts: [Workout]) -> [Row] {
        let cal = Calendar.current
        let cutoff = ISO8601DateFormatter().date(from: "2026-01-01T00:00:00Z")!
        let today = cal.startOfDay(for: Date())

        // Group workouts by calendar date (local time)
        var workoutsByDate: [Date: [Workout]] = [:]
        var earliestDate = today
        for w in workouts {
            let day = cal.startOfDay(for: Date(timeIntervalSince1970: w.startedAt))
            workoutsByDate[day, default: []].append(w)
            if day >= cutoff && day < earliestDate {
                earliestDate = day
            }
        }

        // Pre-2026 workouts go at the end, in order
        let pre2026 = workouts.filter {
            Date(timeIntervalSince1970: $0.startedAt) < cutoff
        }

        // Build rows from today back to the earliest 2026 date
        var rows: [Row] = []
        var date = today
        while date >= earliestDate {
            if let dayWorkouts = workoutsByDate[date] {
                for w in dayWorkouts { rows.append(.workout(w)) }
            } else if date >= cutoff {
                rows.append(.restDay(date.timeIntervalSince1970))
            }
            date = cal.date(byAdding: .day, value: -1, to: date)!
        }

        // Append pre-2026 workouts
        for w in pre2026 { rows.append(.workout(w)) }

        return rows
    }

    /// Determine which workouts had a checkpoint that was a new best at the time.
    /// Workouts are sorted newest-first; we process oldest-first to track the running best.
    private static func computeNewBests(_ workouts: [Workout]) -> Set<Int64> {
        var bestPace: Double? = nil
        var bestCount: Int = 0
        var result = Set<Int64>()

        let cutoff = ISO8601DateFormatter().date(from: "2026-01-01T00:00:00Z")!.timeIntervalSince1970
        for workout in workouts.reversed() {
            guard workout.startedAt >= cutoff,
                  let pace = workout.checkpointPaceSec,
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
