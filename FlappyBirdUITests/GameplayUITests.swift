import XCTest

/// A full run: start, pause, resume, die, and every route off the summary.
final class GameplayUITests: GameUITestCase {

    func testPlayStartsARunWithAPauseControl() {
        launch()
        tap("PLAY")
        XCTAssertTrue(waitFor("II").exists, "No pause control after starting a run")
        capture("gameplay")
    }

    /// Run the pause tests in Zen.
    ///
    /// The overlay is the same in every mode, but in a lethal mode the bird is
    /// falling while the query for the pause control resolves — the run can
    /// reach its summary panel first, which makes the test a coin toss rather
    /// than a check of the overlay. Zen cannot end, so the timing is fixed.
    func testPauseOverlayOffersResumeRestartAndMenu() {
        launch(mode: "zen")
        startRun()
        tap("II")

        for label in ["RESUME", "RESTART", "MENU"] {
            XCTAssertTrue(waitFor(label).exists, "The pause overlay is missing \(label)")
        }
        capture("pause-overlay")

        tap("RESUME")
        waitForDisappearance("RESUME")
        XCTAssertTrue(waitFor("II").exists, "Resuming did not restore the HUD")
    }

    func testPauseThenMenuReturnsToTheMenu() {
        launch(mode: "zen")
        startRun()
        tap("II")
        tap("MENU")
        XCTAssertTrue(waitFor("PLAY").exists, "Leaving a paused run did not reach the menu")
    }

    func testPauseThenRestartBeginsAFreshRun() {
        launch(mode: "zen")
        startRun()
        tap("II")
        tap("RESTART")
        waitForDisappearance("RESTART")
        XCTAssertTrue(waitFor("II").exists, "Restarting did not return to a playable run")
    }

    /// Crash on purpose by never flapping, then check the summary panel.
    func testGameOverPanelAppearsAndPlayAgainWorks() {
        launch()
        startRun()

        let retry = waitFor("PLAY AGAIN", timeout: 25)
        XCTAssertTrue(retry.exists)
        XCTAssertTrue(control("MENU").exists, "The summary panel has no way back to the menu")
        capture("game-over")

        retry.tap()
        waitForDisappearance("PLAY AGAIN")
        XCTAssertTrue(waitFor("II").exists, "PLAY AGAIN did not start another run")
    }

    func testGameOverMenuButtonReturnsToTheMenu() {
        launch()
        startRun()
        waitFor("PLAY AGAIN", timeout: 25)
        tap("MENU")
        XCTAssertTrue(waitFor("PLAY").exists, "The summary panel's MENU button did not go back")
    }

    /// Zen mode bounces instead of ending the run, so no summary may appear.
    func testZenModeDoesNotEndTheRun() {
        launch(mode: "zen")
        startRun()

        // Prove the run is genuinely under way before asserting it never ends:
        // the pause overlay only opens from `.playing`, so a bird still sitting
        // in its ready state would fail here instead of passing by accident.
        tap("II")
        waitFor("RESUME")
        tap("RESUME")
        waitForDisappearance("RESUME")

        let summary = control("PLAY AGAIN")
        XCTAssertFalse(
            summary.waitForExistence(timeout: 12),
            "Zen mode showed a game-over panel"
        )
        XCTAssertTrue(control("II").exists, "Zen mode lost its HUD")
    }
}
