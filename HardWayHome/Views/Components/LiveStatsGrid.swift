import SwiftUI

/// 2x3 grid of live workout statistics.
struct LiveStatsGrid: View {
    let distance: Double
    let elapsedSeconds: Double
    let pace100m: Double?
    let pace1000m: Double?
    let bpm5s: Double?
    let bpm60s: Double?

    var body: some View {
        VStack(spacing: 2) {
            HStack(spacing: 2) {
                StatCell(label: "Distance", value: Formatting.formatDistance(distance))
                StatCell(label: "Time", value: Formatting.formatDuration(elapsedSeconds))
            }
            HStack(spacing: 2) {
                StatCell(label: "Pace (100m)", value: Formatting.formatPace(pace100m))
                StatCell(label: "Pace (1km)", value: Formatting.formatPace(pace1000m))
            }
            HStack(spacing: 2) {
                StatCell(label: "BPM (5s)", value: Formatting.formatBpm(bpm5s))
                StatCell(label: "BPM (60s)", value: Formatting.formatBpm(bpm60s))
            }
        }
    }
}

struct StatCell: View {
    let label: String
    let value: String

    var body: some View {
        VStack(spacing: 6) {
            if !label.isEmpty {
                Text(label.uppercased())
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color(white: 0.56)) // #8E8E93
                    .tracking(0.5)
            }
            Text(value)
                .font(.system(size: 32, weight: .bold).monospacedDigit())
                .foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .padding(.horizontal, 16)
        .background(Color(red: 0.17, green: 0.17, blue: 0.18)) // #2C2C2E
    }
}
