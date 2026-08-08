import SwiftUI

/// 2x4 grid of live workout statistics.
struct LiveStatsGrid: View {
    let distance: Double
    let elapsedSeconds: Double
    let pace100m: Double?
    let pace1000m: Double?
    let bpm5s: Double?
    let bpm60s: Double?
    let returnDistance: Double?
    let returnIsCrowFlies: Bool
    let returnEtaSeconds: Double?

    var body: some View {
        VStack(spacing: 2) {
            row {
                StatCell(label: "Distance", value: Formatting.formatDistance(distance))
                StatCell(label: "Time", value: Formatting.formatDuration(elapsedSeconds))
            }
            row {
                StatCell(label: "Pace (100m)", value: Formatting.formatPace(pace100m))
                StatCell(label: "Pace (1km)", value: Formatting.formatPace(pace1000m))
            }
            row {
                StatCell(label: "BPM (5s)", value: Formatting.formatBpm(bpm5s))
                StatCell(label: "BPM (60s)", value: Formatting.formatBpm(bpm60s))
            }
            row {
                StatCell(label: "Return",
                         value: returnDistance != nil
                             ? Formatting.formatDistance(returnDistance) : "--",
                         valueColor: returnIsCrowFlies ? crowFliesRed : .white,
                         subLabel: returnIsCrowFlies ? "crow flies" : nil)
                StatCell(label: "Return ETA",
                         value: returnEtaSeconds != nil
                             ? Formatting.formatDuration(returnEtaSeconds!) : "--:--")
            }
        }
    }

    /// A row of equal-height cells: the crow-flies sub-label makes the Return
    /// cell taller than its neighbour, so stretch cells to the row height.
    private func row(@ViewBuilder content: () -> some View) -> some View {
        HStack(spacing: 2, content: content)
            .fixedSize(horizontal: false, vertical: true)
    }
}

private let crowFliesRed = Color(red: 1.0, green: 0.27, blue: 0.23) // #FF453A

struct StatCell: View {
    let label: String
    let value: String
    var valueColor: Color = .white
    var subLabel: String? = nil

    var body: some View {
        VStack(spacing: 6) {
            if !label.isEmpty {
                Text(label.uppercased())
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color(white: 0.56)) // #8E8E93
                    .tracking(0.5)
            }
            Text(value)
                .font(.system(size: 28, weight: .bold).monospacedDigit())
                .foregroundStyle(valueColor)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            if let subLabel {
                Text(subLabel.uppercased())
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(valueColor)
                    .tracking(0.5)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, 20)
        .padding(.horizontal, 12)
        .background(Color(red: 0.17, green: 0.17, blue: 0.18)) // #2C2C2E
    }
}
