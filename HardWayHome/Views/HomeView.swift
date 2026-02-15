import SwiftUI

struct HomeView: View {
    @Bindable var vm: WorkoutRecordingVM
    @State private var showBlePicker = false
    @State private var workouts: [Workout] = []
    let onSelectWorkout: (Int64) -> Void
    let onOpenSettings: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Status bar
            HStack {
                GpsStatusPill(status: vm.locationService.gpsStatus,
                              accuracy: vm.locationService.accuracy)
                HrStatusPill(connectionState: vm.heartRateService.connectionState,
                             currentBpm: vm.heartRateService.currentBpm,
                             onTap: { showBlePicker = true })
                BackupStatusPill(status: vm.backupService.status,
                                 onTap: onOpenSettings)
                Spacer()
                Button(action: onOpenSettings) {
                    Text("⚙")
                        .font(.system(size: 22))
                        .foregroundStyle(Color(white: 0.56))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            // Start button
            Button(action: { vm.start() }) {
                Text("Start")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                    .background(.green)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)

            // Workout history
            WorkoutHistoryList(workouts: workouts, onSelect: onSelectWorkout)
        }
        .onAppear { loadHistory() }
        .sheet(isPresented: $showBlePicker) {
            BleDevicePicker(
                connectionState: vm.heartRateService.connectionState,
                devices: vm.heartRateService.discoveredDevices,
                lastDevice: vm.heartRateService.lastDevice,
                onScan: { vm.heartRateService.startScan() },
                onStopScan: { vm.heartRateService.stopScan() },
                onConnect: { vm.heartRateService.connect(to: $0) },
                onDisconnect: { vm.heartRateService.disconnect() },
                onClose: { showBlePicker = false })
        }
    }

    private func loadHistory() {
        workouts = (try? AppDatabase.shared.getWorkoutHistory()) ?? []
    }
}
