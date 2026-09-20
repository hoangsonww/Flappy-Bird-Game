import XCTest

/// The replay list and the playback screen.
final class ReplayUITests: GameUITestCase {

    func testTheMenuOffersReplays() {
        launch()
        XCTAssertTrue(waitFor("REPLAYS").exists, "REPLAYS is missing from the menu")
    }

    func testTheListShowsRecordedRuns() {
        launch(screen: "replays")
        waitFor("‹")
        waitForLabel(containing: "pts")
        capture("replays")
    }

    func testTheListReturnsToTheMenu() {
        launch(screen: "replays")
        tap("‹")
        XCTAssertTrue(waitFor("PLAY").exists)
    }

    /// Opening a row has to reach playback, and playback has to say so.
    func testOpeningAReplayStartsPlayback() throws {
        launch(screen: "replays")
        try openFirstReplay()

        waitForLabel(containing: "Replay")
        XCTAssertTrue(waitFor("PAUSE").exists, "Playback should start running")
        XCTAssertTrue(control("RESTART").exists)
        capture("replay-playback")
    }

    func testPauseAndResumeToggleTheControl() throws {
        launch(screen: "replays")
        try openFirstReplay()

        tap("PAUSE")
        XCTAssertTrue(waitFor("PLAY").exists, "PAUSE should become PLAY")

        tap("PLAY")
        XCTAssertTrue(waitFor("PAUSE").exists, "PLAY should become PAUSE again")
    }

    /// Restarting from a paused replay must resume it, not leave it stopped.
    func testRestartResumesFromTheBeginning() throws {
        launch(screen: "replays")
        try openFirstReplay()

        tap("PAUSE")
        waitFor("PLAY")
        tap("RESTART")

        XCTAssertTrue(waitFor("PAUSE").exists, "RESTART should leave the replay playing")
    }

    func testPlaybackReturnsToTheList() throws {
        launch(screen: "replays")
        try openFirstReplay()

        tap("‹")
        waitForLabel(containing: "pts")
        XCTAssertTrue(control("‹").exists, "Should be back on the list")
    }

    /// The elapsed time has to actually advance, or nothing is being played.
    func testTheClockAdvancesWhilePlaying() throws {
        launch(screen: "replays")
        try openFirstReplay()

        // The scene has only just been presented, so wait for the clock to be
        // published before reading it — a bare read here is the same race this
        // suite hit everywhere else.
        waitForLabels("the playback clock") { _ in self.elapsedLabel() != nil }
        let first = try XCTUnwrap(elapsedLabel(), "No playback clock on screen")

        waitForLabels("the playback clock to advance") { _ in
            guard let now = self.elapsedLabel() else { return false }
            return now != first
        }
    }

    // MARK: - Helpers

    /// The transport's "0.0s / 44.0s" readout.
    private func elapsedLabel() -> String? {
        visibleLabels().first { $0.contains("s / ") }
    }

    private func openFirstReplay() throws {
        waitForLabel(containing: "pts")
        let row = try XCTUnwrap(
            snapshotElements().first { element in
                element.elementType == .button && element.label.contains("points")
            },
            "No replay row on the list. On screen: \(visibleLabels())"
        )
        tap(snapshot: row)
    }
}
