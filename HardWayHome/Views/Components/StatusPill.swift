import SwiftUI

/// A small colored pill used for GPS, HR, and Backup status indicators.
struct StatusPill: View {
    let label: String
    let color: Color

    var body: some View {
        Text(label)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(color)
            .clipShape(Capsule())
    }
}

// MARK: - GPS Status

struct GpsStatusPill: View {
    let status: GpsStatus
    let accuracy: Double?

    var body: some View {
        StatusPill(label: label, color: color)
    }

    private var color: Color {
        switch status {
        case .none: .red
        case .poor: .yellow
        case .good: .green
        }
    }

    private var label: String {
        let base = status == .none ? "No GPS" : "GPS"
        if let acc = accuracy {
            return "\(base) ±\(Int(acc))m"
        }
        return base
    }
}

// MARK: - HR Status

struct HrStatusPill: View {
    let connectionState: HrConnectionState
    let currentBpm: Int?
    var onTap: (() -> Void)? = nil

    var body: some View {
        Button(action: { onTap?() }) {
            StatusPill(label: label, color: color)
        }
    }

    private var color: Color {
        switch connectionState {
        case .connected:
            currentBpm != nil ? .green : .yellow
        case .connecting, .scanning:
            .yellow
        case .disconnected:
            .red
        }
    }

    private var label: String {
        switch connectionState {
        case .connected:
            if let bpm = currentBpm { return "♥ \(bpm)" }
            return "♥ --"
        case .connecting, .scanning:
            return "♥ ..."
        case .disconnected:
            return "♥ ✕"
        }
    }
}

// MARK: - Backup Status

struct BackupStatusPill: View {
    let status: BackupStatus
    var onTap: (() -> Void)? = nil

    var body: some View {
        Button(action: { onTap?() }) {
            StatusPill(label: label, color: color)
        }
    }

    private var color: Color {
        switch status {
        case .notConfigured: .gray
        case .idle, .success: .green
        case .inProgress: .yellow
        case .failed: .red
        }
    }

    private var label: String {
        switch status {
        case .notConfigured: "☁ --"
        case .idle, .success: "☁ ✓"
        case .inProgress: "☁ ..."
        case .failed: "☁ ✕"
        }
    }
}
