import SwiftUI

enum AppRoute: Hashable {
    case workout
    case workoutDetail(Int64)
    case settings
}

@main
struct HardWayHomeApp: App {
    @State private var vm = WorkoutRecordingVM()
    @State private var path = NavigationPath()
    @State private var isReady = false

    var body: some Scene {
        WindowGroup {
            Group {
                if isReady {
                    NavigationStack(path: $path) {
                        HomeView(
                            vm: vm,
                            onSelectWorkout: { id in path.append(AppRoute.workoutDetail(id)) },
                            onOpenSettings: { path.append(AppRoute.settings) })
                        .navigationDestination(for: AppRoute.self) { route in
                            switch route {
                            case .workout:
                                WorkoutView(vm: vm)
                                    .navigationBarBackButtonHidden()
                            case .workoutDetail(let id):
                                WorkoutDetailView(workoutId: id, onBack: { path.removeLast() })
                                    .navigationBarBackButtonHidden()
                            case .settings:
                                SettingsView(
                                    vm: SettingsVM(backupService: vm.backupService),
                                    onBack: { path.removeLast() })
                                .navigationBarBackButtonHidden()
                            }
                        }
                    }
                } else {
                    Color.black.ignoresSafeArea()
                }
            }
            .preferredColorScheme(.dark)
            .task {
                await vm.initialize()
                isReady = true
                // Auto-navigate to workout if one is active (resume after kill)
                if vm.activeWorkout != nil {
                    path.append(AppRoute.workout)
                }
            }
            .onChange(of: vm.activeWorkout?.id) { oldId, newId in
                if newId != nil, oldId == nil {
                    // Workout just started — navigate to workout screen
                    path.append(AppRoute.workout)
                } else if newId == nil, oldId != nil {
                    // Workout ended — pop back to home
                    path = NavigationPath()
                }
            }
        }
    }
}
