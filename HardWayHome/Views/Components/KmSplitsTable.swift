import SwiftUI

/// Table of per-kilometre splits.
struct KmSplitsTable: View {
    let splits: [KmSplit]

    var body: some View {
        if splits.isEmpty { return AnyView(EmptyView()) }

        return AnyView(
            VStack(alignment: .leading, spacing: 0) {
                Text("Km Splits")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.bottom, 12)

                // Header
                HStack {
                    Text("KM")
                        .frame(width: 50, alignment: .leading)
                    Spacer()
                    Text("TIME")
                        .frame(width: 80, alignment: .trailing)
                    Text("AV BPM")
                        .frame(width: 80, alignment: .trailing)
                }
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color(white: 0.56))
                .tracking(0.5)
                .padding(.vertical, 10)
                .overlay(alignment: .bottom) {
                    Divider().background(Color(white: 0.22))
                }

                // Rows
                ForEach(splits, id: \.km) { split in
                    HStack {
                        Text("\(split.km)")
                            .frame(width: 50, alignment: .leading)
                        Spacer()
                        Text(Formatting.formatPace(split.seconds))
                            .frame(width: 80, alignment: .trailing)
                        Text(Formatting.formatBpm(split.avgBpm))
                            .frame(width: 80, alignment: .trailing)
                    }
                    .font(.system(size: 15).monospacedDigit())
                    .foregroundStyle(.white)
                    .padding(.vertical, 12)
                    .overlay(alignment: .bottom) {
                        Divider().background(Color(white: 0.17))
                    }
                }
            }
            .padding(.top, 24)
            .padding(.horizontal, 16)
        )
    }
}
