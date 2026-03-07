import Testing
@testable import HardWayHome

@Suite("Navigation layout")
struct NavigationTests {

    @Test("HomeView stays mounted for detail/stats/settings (preserves scroll position)")
    func homeViewStaysMounted() {
        #expect(AppScreen.home.keepsHomeMounted)
        #expect(AppScreen.workoutDetail(42).keepsHomeMounted)
        #expect(AppScreen.stats.keepsHomeMounted)
        #expect(AppScreen.settings.keepsHomeMounted)
    }

    @Test("HomeView is NOT mounted during active workout")
    func homeViewNotMountedDuringWorkout() {
        #expect(!AppScreen.workout.keepsHomeMounted)
    }

    @Test("Every non-home screen that keeps HomeView mounted is an opaque overlay")
    func overlayScreensCoverHome() {
        for screen in AppScreen.allNonParametric where screen.keepsHomeMounted && screen != .home {
            #expect(screen.isOpaqueOverlay,
                    "Screen \(screen) keeps HomeView mounted but is not an opaque overlay — users will see overlapping text")
        }
    }

    @Test("Home and workout screens are not overlays")
    func nonOverlayScreens() {
        #expect(!AppScreen.home.isOpaqueOverlay)
        #expect(!AppScreen.workout.isOpaqueOverlay)
    }
}
