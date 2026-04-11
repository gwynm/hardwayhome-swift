import XCTest

@MainActor
final class WorkoutFlowTests: XCTestCase {

    private func launchApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting"]
        app.launch()
        return app
    }

    /// Swipe the slide-to-finish thumb to trigger the stop alert.
    private func slideToFinish(app: XCUIApplication) {
        // The thumb chevron image carries the slideToFinish identifier
        let thumb = app.images["slideToFinish"]
        guard thumb.exists else { return }

        // Drag from the thumb all the way to the right edge
        let start = thumb.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        // Drag far to the right (350pt from thumb) to exceed the 85% threshold
        let end = start.withOffset(CGVector(dx: 350, dy: 0))
        start.press(forDuration: 0.1, thenDragTo: end)
    }

    /// Happy path: start a workout, slide to finish, save it,
    /// and verify the home screen returns.
    func testStartAndFinishWorkout() {
        let app = launchApp()

        let startButton = app.buttons["startButton"]
        XCTAssertTrue(startButton.waitForExistence(timeout: 10),
                      "Start button should appear on home screen")

        // --- Start workout ---
        startButton.tap()

        let slideText = app.staticTexts["slideToFinish"]
        XCTAssertTrue(slideText.waitForExistence(timeout: 5),
                      "Workout screen should appear with slide-to-finish")

        // Let the workout run briefly
        sleep(2)

        // --- Slide to finish ---
        slideToFinish(app: app)

        // --- Tap "Finish & Save" in the alert ---
        let finishButton = app.buttons["Finish & Save"]
        XCTAssertTrue(finishButton.waitForExistence(timeout: 3),
                      "Stop Workout alert should appear")
        finishButton.tap()

        // --- Verify we're back on home screen ---
        XCTAssertTrue(startButton.waitForExistence(timeout: 10),
                      "Should return to home screen after saving")
    }

    /// Start a workout and discard it (short workout, no confirmation).
    func testStartAndDiscardWorkout() {
        let app = launchApp()

        let startButton = app.buttons["startButton"]
        XCTAssertTrue(startButton.waitForExistence(timeout: 10))

        startButton.tap()

        let slideText = app.staticTexts["slideToFinish"]
        XCTAssertTrue(slideText.waitForExistence(timeout: 5))

        // --- Slide to finish ---
        slideToFinish(app: app)

        // Tap "Finish & Delete"
        let deleteButton = app.buttons["Finish & Delete"]
        XCTAssertTrue(deleteButton.waitForExistence(timeout: 3))
        deleteButton.tap()

        // Should return to home screen
        XCTAssertTrue(startButton.waitForExistence(timeout: 5),
                      "Should return to home screen after discarding")
    }
}
