import SwiftUI

enum AppScreen: Equatable {
    case home
    case workout
    case workoutDetail(Int64)
    case stats
    case settings
}

@main
struct HardWayHomeApp: App {
    @State private var vm = WorkoutRecordingVM()
    @State private var screen: AppScreen = .home
    @State private var isReady = false

    var body: some Scene {
        WindowGroup {
            Group {
                if isReady {
                    screenView
                } else {
                    Color.black.ignoresSafeArea()
                }
            }
            .preferredColorScheme(.dark)
            .task {
                await vm.initialize()
                isReady = true
                if vm.activeWorkout != nil {
                    screen = .workout
                }
            }
            .onChange(of: vm.activeWorkout?.id) { oldId, newId in
                if newId != nil, oldId == nil {
                    screen = .workout
                } else if newId == nil, oldId != nil {
                    screen = .home
                }
            }
        }
    }

    @ViewBuilder
    private var screenView: some View {
        switch screen {
        case .home:
            HomeView(
                vm: vm,
                onSelectWorkout: { id in screen = .workoutDetail(id) },
                onOpenStats: { screen = .stats },
                onOpenSettings: { screen = .settings })
        case .workout:
            WorkoutView(vm: vm)
        case .workoutDetail(let id):
            WorkoutDetailView(workoutId: id, onBack: { screen = .home })
        case .stats:
            YearlyStatsView(
                vm: YearlyStatsVM(),
                onBack: { screen = .home })
        case .settings:
            SettingsView(
                vm: SettingsVM(backupService: vm.backupService),
                onBack: { screen = .home })
        }
    }
}
