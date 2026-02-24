import SwiftUI
import Charts

struct HeartRateChartView: View {
    let pulses: [Pulse]
    let workoutStartedAt: TimeInterval
    let elapsedSeconds: Double

    private var xMaxMinutes: Double {
        max(60, elapsedSeconds / 60)
    }

    private var dataPoints: [(minutes: Double, bpm: Double)] {
        let raw = pulses.map { pulse in
            (minutes: (pulse.createdAt - workoutStartedAt) / 60, bpm: Double(pulse.bpm))
        }
        guard raw.count >= 3 else { return raw }

        let window = max(3, raw.count / 40) | 1
        let half = window / 2
        return raw.indices.map { i in
            let lo = max(0, i - half)
            let hi = min(raw.count - 1, i + half)
            let slice = raw[lo...hi]
            let avg = slice.map(\.bpm).reduce(0, +) / Double(slice.count)
            return (minutes: raw[i].minutes, bpm: avg)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("HEART RATE")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color(white: 0.56))
                .tracking(0.5)
                .padding(.horizontal, 16)

            Chart {
                ForEach(Array(dataPoints.enumerated()), id: \.offset) { _, point in
                    LineMark(
                        x: .value("Time", point.minutes),
                        y: .value("BPM", point.bpm)
                    )
                    .foregroundStyle(Color.red)
                    .lineStyle(StrokeStyle(lineWidth: 1.5))

                    AreaMark(
                        x: .value("Time", point.minutes),
                        y: .value("BPM", point.bpm)
                    )
                    .foregroundStyle(
                        .linearGradient(
                            colors: [Color.red.opacity(0.3), Color.red.opacity(0.0)],
                            startPoint: .top, endPoint: .bottom))
                }
            }
            .chartXScale(domain: 0...xMaxMinutes)
            .chartYScale(domain: 0...200)
            .chartXAxis {
                AxisMarks(values: .stride(by: xAxisStride)) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                        .foregroundStyle(Color(white: 0.25))
                    AxisValueLabel {
                        if let mins = value.as(Double.self) {
                            Text("\(Int(mins))m")
                                .font(.system(size: 10))
                                .foregroundStyle(Color(white: 0.56))
                        }
                    }
                }
            }
            .chartYAxis {
                AxisMarks(values: [0, 40, 80, 120, 160, 200]) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                        .foregroundStyle(Color(white: 0.3))
                    AxisValueLabel {
                        if let bpm = value.as(Int.self) {
                            Text("\(bpm)")
                                .font(.system(size: 10))
                                .foregroundStyle(Color(white: 0.56))
                        }
                    }
                }
            }
            .chartPlotStyle { plotArea in
                plotArea.background(Color(white: 0.08))
            }
            .frame(height: 220)
            .padding(.horizontal, 16)
        }
        .padding(.top, 24)
    }

    private var xAxisStride: Double {
        switch xMaxMinutes {
        case ..<20: return 5
        case ..<45: return 10
        case ..<90: return 15
        default: return 30
        }
    }
}
