import SwiftUI

struct YearlyStatsView: View {
    @Bindable var vm: YearlyStatsVM
    let onBack: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Button(action: onBack) {
                        Text("← Back")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(.blue)
                    }
                    Spacer()
                    Text("Stats")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(.white)
                    Spacer()
                    Color.clear.frame(width: 60)
                }
                .padding(.bottom, 32)

                if vm.isLoading {
                    ProgressView()
                        .tint(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 40)
                } else {
                    headerRow

                    if let projected = vm.projected {
                        statsRow(label: "Projected", stats: projected, highlight: true)
                        divider
                    }

                    ForEach(vm.yearlyStats) { stats in
                        statsRow(label: String(stats.year), stats: stats)
                        divider
                    }

                    Text("Recovery or death.")
                        .font(.system(size: 12))
                        .foregroundStyle(Color(white: 0.39))
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 32)
                }
            }
            .padding(16)
            .padding(.bottom, 40)
        }
        .onAppear { vm.load() }
    }

    private var headerRow: some View {
        HStack {
            Text("Year")
                .frame(width: 56, alignment: .leading)
            Text("Run")
                .frame(width: 44, alignment: .trailing)
            Text("Walk")
                .frame(width: 44, alignment: .trailing)
            Text("Pace")
                .frame(width: 48, alignment: .trailing)
        }
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(Color(white: 0.56))
        .padding(.bottom, 8)
    }

    private func statsRow(label: String, stats: YearlyStats, highlight: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .font(.system(size: highlight ? 10 : 13, design: .monospaced))
                    .frame(width: 56, alignment: .leading)
                Text(String(format: "%.0f", stats.runKm))
                    .frame(width: 44, alignment: .trailing)
                Text(String(format: "%.0f", stats.walkKm))
                    .frame(width: 44, alignment: .trailing)
                Text(Formatting.formatPace(stats.avgRunPaceSecPerKm))
                    .frame(width: 48, alignment: .trailing)
            }
            .font(.system(size: 13, design: .monospaced))
            .foregroundStyle(highlight ? .yellow : .white)

            if !stats.dailyActivity.isEmpty {
                ActivitySparkBars(
                    daily: stats.dailyActivity,
                    daysInYear: daysInYear(stats.year),
                    maxDailyKm: vm.maxDailyKm
                )
                .frame(height: 32)
            }
        }
        .padding(.vertical, 6)
    }

    private var divider: some View {
        Rectangle()
            .fill(Color(white: 0.25))
            .frame(height: 0.5)
    }

    private func daysInYear(_ year: Int) -> Int {
        let calendar = Calendar.current
        let jan1 = calendar.date(from: DateComponents(year: year, month: 1, day: 1))!
        return calendar.range(of: .day, in: .year, for: jan1)?.count ?? 365
    }
}

// MARK: - Sparkline bar chart

private struct ActivitySparkBars: View {
    let daily: [DayActivity]
    let daysInYear: Int
    let maxDailyKm: Double

    var body: some View {
        Canvas { context, size in
            guard maxDailyKm > 0 else { return }

            let barWidth = size.width / CGFloat(daysInYear)
            let maxHeight = size.height

            for day in daily {
                let x = CGFloat(day.dayOfYear - 1) * barWidth
                var yOffset: CGFloat = 0

                for seg in day.segments {
                    let segHeight = maxHeight * CGFloat(seg.km / maxDailyKm)
                    let rect = CGRect(
                        x: x,
                        y: maxHeight - yOffset - segHeight,
                        width: max(barWidth - 0.5, 0.5),
                        height: segHeight
                    )
                    context.fill(Path(rect), with: .color(paceColor(seg.paceSecPerKm)))
                    yOffset += segHeight
                }
            }
        }
    }

    private func paceColor(_ secPerKm: Double) -> Color {
        // <5:00 (300s) = bright red, >10:00 (600s) = deep blue
        let t = min(max((secPerKm - 300) / 300, 0), 1)
        let hue = t * 240 / 360
        return Color(hue: hue, saturation: 0.85, brightness: 0.95)
    }
}
