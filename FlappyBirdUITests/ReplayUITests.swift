import XCTest

/// The replay list and the playback screen.
///
/// Every test that needs a replay **plays a run to make one**. Nothing is
/// seeded: a replay is a recording, and the list is empty until there is
/// something real in it.
final class ReplayUITests: GameUITestCase {

    func testTheMenuOffersReplays() {
        launch()
        XCTAssertTrue(waitFor("REPLAYS").exists, "REPLAYS is missing from the menu")
    }

    /// Seeding must never invent recordings.
    func testTheListIsEmptyUntilARunIsPlayed() {
        launch(screen: "replays")
        waitFor("‹")
        waitForLabels("the empty-state message") { labels in
            labels.contains { $0.contains("No replays yet") }
        }
        XCTAssertFalse(
            visibleLabels().contains { $0.contains("pts") },
            "The list should hold no fabricated entries"
        )
        capture("replays-empty")
    }

    func testAFinishedRunAppearsInTheList() throws {
        try playARun()
        openReplays()
        waitForLabel(containing: "pts")
        capture("replays")
    }

    func testTheListReturnsToTheMenu() {
        launch(screen: "replays")
        tap("‹")
        XCTAssertTrue(waitFor("PLAY").exists)
    }

    func testOpeningAReplayStartsPlayback() throws {
        try playARun()
        openReplays()
        try openFirstReplay()

        waitForLabel(containing: "Replay")
        XCTAssertTrue(waitFor("PAUSE").exists, "Playback should start running")
        XCTAssertTrue(control("RESTART").exists)
        capture("replay-playback")
    }

    func testPauseAndResumeToggleTheControl() throws {
        try playARun()
        openReplays()
        try openFirstReplay()

        tap("PAUSE")
        XCTAssertTrue(waitFor("PLAY").exists, "PAUSE should become PLAY")

        tap("PLAY")
        XCTAssertTrue(waitFor("PAUSE").exists, "PLAY should become PAUSE again")
    }

    /// Restarting from a paused replay must resume it, not leave it stopped.
    func testRestartResumesFromTheBeginning() throws {
        try playARun()
        openReplays()
        try openFirstReplay()

        tap("PAUSE")
        waitFor("PLAY")
        tap("RESTART")

        XCTAssertTrue(waitFor("PAUSE").exists, "RESTART should leave the replay playing")
    }

    func testPlaybackReturnsToTheList() throws {
        try playARun()
        openReplays()
        try openFirstReplay()

        tap("‹")
        waitForLabel(containing: "pts")
        XCTAssertTrue(control("‹").exists, "Should be back on the list")
    }

    /// The elapsed time has to actually advance, or nothing is being played.
    func testTheClockAdvancesWhilePlaying() throws {
        try playARun()
        openReplays()
        try openFirstReplay()

        waitForLabels("the playback clock") { _ in self.elapsedLabel() != nil }
        let first = try XCTUnwrap(elapsedLabel(), "No playback clock on screen")

        waitForLabels("the playback clock to advance") { _ in
            guard let now = self.elapsedLabel() else { return false }
            return now != first
        }
    }

    // MARK: - Helpers

    /// Record a real run of a known length.
    ///
    /// The auto-pilot flies and the run ends on cue, because a hand-flown run
    /// here lasts about a second and a half — long enough to record, too short
    /// to pause and resume before playback runs out.
    private func playARun() throws {
        launch(autoPilot: 6)
        waitFor("PLAY AGAIN", timeout: 30)
    }

    /// Relaunch straight into the list.
    ///
    /// Navigating there from the summary panel would mean crossing the menu
    /// while the attract-mode flag is still driving the app. Recordings survive
    /// a relaunch — nothing is seeded, so nothing clears them — which makes
    /// this both simpler and independent of how the menu behaves.
    private func openReplays() {
        launch(screen: "replays", seedDemoData: false)
        waitFor("‹")
    }

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
