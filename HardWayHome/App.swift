import SwiftUI

enum AppScreen: Equatable {
    case home
    case workout
    case workoutDetail(Int64)
    case stats
    case settings

    static var allNonParametric: [AppScreen] {
        [.home, .workout, .workoutDetail(0), .stats, .settings]
    }

    /// HomeView stays mounted (in a ZStack) to preserve scroll position.
    var keepsHomeMounted: Bool {
        self != .workout
    }

    /// This screen covers HomeView and needs an opaque background.
    var isOpaqueOverlay: Bool {
        switch self {
        case .workoutDetail, .stats, .settings: return true
        case .home, .workout: return false
        }
    }
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
        if screen.keepsHomeMounted {
            ZStack {
                HomeView(
                    vm: vm,
                    onSelectWorkout: { id in screen = .workoutDetail(id) },
                    onOpenStats: { screen = .stats },
                    onOpenSettings: { screen = .settings })

                if case .workoutDetail(let id) = screen {
                    WorkoutDetailView(workoutId: id, onBack: { screen = .home })
                        .background(Color(.systemBackground).ignoresSafeArea())
                }
                if case .stats = screen {
                    YearlyStatsView(
                        vm: YearlyStatsVM(),
                        onBack: { screen = .home })
                    .background(Color(.systemBackground).ignoresSafeArea())
                }
                if case .settings = screen {
                    SettingsView(
                        vm: SettingsVM(backupService: vm.backupService),
                        onBack: { screen = .home })
                    .background(Color(.systemBackground).ignoresSafeArea())
                }
            }
        } else {
            WorkoutView(vm: vm)
        }
    }
}
