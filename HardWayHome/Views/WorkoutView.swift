import SwiftUI

struct WorkoutView: View {
    @Bindable var vm: WorkoutRecordingVM
    @State private var statsVM = WorkoutStatsVM()
    @State private var showBlePicker = false
    @State private var showStopAlert = false
    @State private var showDiscardAlert = false

    var body: some View {
        if let workout = vm.activeWorkout {
            ScrollView {
                VStack(spacing: 0) {
                    // Status indicators
                    HStack {
                        GpsStatusPill(status: vm.locationService.gpsStatus,
                                      accuracy: vm.locationService.accuracy)
                        HrStatusPill(connectionState: vm.heartRateService.connectionState,
                                     currentBpm: vm.heartRateService.currentBpm,
                                     onTap: { showBlePicker = true })
                        BackupStatusPill(status: vm.backupService.status)
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)

                    // Stop button
                    Button(action: { showStopAlert = true }) {
                        Text("Stop")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 18)
                            .background(.red)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)

                    // Live stats grid
                    LiveStatsGrid(
                        distance: statsVM.distance,
                        elapsedSeconds: statsVM.elapsedSeconds,
                        pace100m: statsVM.pace100m,
                        pace1000m: statsVM.pace1000m,
                        bpm5s: statsVM.bpm5s,
                        bpm60s: statsVM.bpm60s)
                    .padding(.horizontal, 16)

                    // Km splits
                    KmSplitsTable(splits: statsVM.splits)

                    // Route map
                    RouteMapView(trackpoints: statsVM.trackpoints)
                }
                .padding(.bottom, 40)
            }
            .onAppear {
                UIApplication.shared.isIdleTimerDisabled = true
                statsVM.observe(workoutId: workout.id!, startedAt: workout.startedAt)
            }
            .onDisappear {
                UIApplication.shared.isIdleTimerDisabled = false
                statsVM.stop()
            }
            .alert("Stop Workout", isPresented: $showStopAlert) {
                Button("Cancel", role: .cancel) {}
                Button("Finish & Save") { vm.finish() }
                Button("Finish & Delete", role: .destructive) {
                    if statsVM.distance > 500 {
                        showDiscardAlert = true
                    } else {
                        vm.discard()
                    }
                }
            }
            .alert("Are you sure?", isPresented: $showDiscardAlert) {
                Button("Cancel", role: .cancel) {}
                Button("Delete", role: .destructive) { vm.discard() }
            } message: {
                Text("You have \(String(format: "%.1f", statsVM.distance / 1000)) km of data. This cannot be undone.")
            }
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
        } else {
            Text("No active workout")
                .font(.system(size: 17))
                .foregroundStyle(Color(white: 0.56))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
