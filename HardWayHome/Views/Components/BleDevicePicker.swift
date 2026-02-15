import SwiftUI

/// Sheet for scanning and connecting to BLE heart rate monitors.
struct BleDevicePicker: View {
    let connectionState: HrConnectionState
    let devices: [HrDevice]
    let lastDevice: HrDevice?
    let onScan: () -> Void
    let onStopScan: () -> Void
    let onConnect: (String) -> Void
    let onDisconnect: () -> Void
    let onClose: () -> Void

    var body: some View {
        NavigationStack {
            ZStack {
                Color(red: 0.11, green: 0.11, blue: 0.12) // #1C1C1E
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    if connectionState == .connected {
                        connectedView
                    } else if connectionState == .connecting {
                        connectingView
                    } else {
                        scanView
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { onClose() }
                        .foregroundStyle(.blue)
                        .fontWeight(.semibold)
                }
            }
            .navigationTitle("Heart Rate Monitor")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
        .onAppear {
            if connectionState == .disconnected {
                onScan()
            }
        }
        .onDisappear {
            onStopScan()
        }
    }

    private var connectedView: some View {
        VStack(spacing: 12) {
            Text("Connected to \(lastDevice?.name ?? "HR Monitor")")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.green)
            Button(action: onDisconnect) {
                Text("Disconnect")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.red)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(Color(white: 0.17))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
        .padding(20)
    }

    private var connectingView: some View {
        VStack(spacing: 12) {
            ProgressView()
                .tint(.white)
            Text("Connecting...")
                .font(.system(size: 15))
                .foregroundStyle(Color(white: 0.56))
        }
        .padding(40)
    }

    private var scanView: some View {
        VStack(spacing: 0) {
            // Scan header
            HStack {
                Text("AVAILABLE DEVICES")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color(white: 0.56))
                    .tracking(0.5)
                Spacer()
                if connectionState == .scanning {
                    ProgressView()
                        .tint(.blue)
                } else {
                    Button("Scan") { onScan() }
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.blue)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)

            if devices.isEmpty {
                Text(connectionState == .scanning
                     ? "Scanning for heart rate monitors..."
                     : "No heart rate monitors found.\nMake sure your device is on and in range.")
                    .font(.system(size: 15))
                    .foregroundStyle(Color(white: 0.56))
                    .multilineTextAlignment(.center)
                    .padding(40)
            }

            List(devices) { device in
                Button(action: { onConnect(device.id) }) {
                    HStack {
                        Text(device.name ?? "Unknown Device")
                            .foregroundStyle(.white)
                        Spacer()
                        Text(String(device.id.prefix(8)) + "...")
                            .font(.system(size: 13))
                            .foregroundStyle(Color(white: 0.56))
                    }
                }
                .listRowBackground(Color(red: 0.11, green: 0.11, blue: 0.12))
            }
            .listStyle(.plain)
        }
    }
}
