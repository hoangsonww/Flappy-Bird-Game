import XCTest

/// The menu: mode selection and every route out of it.
final class MenuUITests: GameUITestCase {

    func testMenuOffersEveryDestination() {
        launch()
        for label in ["PLAY", "LEADERBOARD", "ACHIEVEMENTS", "SHOP", "STATS", "SETTINGS", "◀", "▶"] {
            XCTAssertTrue(waitFor(label).exists, "\(label) missing from the menu")
        }
        capture("menu")
    }

    /// The arrows must stay inside the card, not sit on its border.
    func testModeArrowsSitInsideTheModeCard() {
        launch()
        let previous = waitFor("◀")
        let next = waitFor("▶")
        let play = waitFor("PLAY")

        // `PLAY` spans the same width as the mode card, so it stands in for the
        // card's edges — the arrows have to be comfortably inside them.
        let gutter: CGFloat = 6
        XCTAssertGreaterThan(
            previous.frame.minX - play.frame.minX, gutter,
            "The left arrow is flush against the card border"
        )
        XCTAssertGreaterThan(
            play.frame.maxX - next.frame.maxX, gutter,
            "The right arrow is flush against the card border"
        )
        XCTAssertLessThan(previous.frame.maxX, next.frame.minX, "The arrows overlap")
    }

    func testCyclingForwardAndBackReturnsToTheSameMode() {
        launch()
        let modes = ["CLASSIC", "ENDLESS", "TIME ATTACK", "HARDCORE", "ZEN", "DAILY"]

        func currentMode() -> String? {
            visibleLabels().first { label in modes.contains { label.contains($0) } }
        }

        let start = currentMode()
        XCTAssertNotNil(start, "No mode name on the card. On screen: \(visibleLabels())")

        tap("▶")
        let advanced = currentMode()
        XCTAssertNotEqual(advanced, start, "The right arrow did not change the mode")

        tap("◀")
        XCTAssertEqual(currentMode(), start, "Cycling back did not restore the mode")
    }

    func testEveryModeIsReachableAndKeepsItsLayout() {
        launch()
        let play = waitFor("PLAY")

        // One full lap of the selector. Each stop must keep its labels inside
        // the card — long subtitles used to run underneath the arrows.
        for step in 0..<GameMode.selectableCount {
            tap("▶")
            let labels = visibleLabels()
            XCTAssertFalse(labels.isEmpty, "Step \(step) left the card blank")
            for element in app.staticTexts.allElementsBoundByIndex where element.frame.width > 0 {
                XCTAssertLessThanOrEqual(
                    element.frame.width, play.frame.width,
                    "\"\(element.label)\" is wider than the mode card at step \(step)"
                )
            }
        }
        capture("menu-after-cycling")
    }

    func testEachDestinationOpensAndComesBack() {
        launch()
        for destination in ["LEADERBOARD", "ACHIEVEMENTS", "SHOP", "STATS", "SETTINGS"] {
            tap(destination)
            // The back chevron only exists on a list screen, so finding it
            // proves the transition actually happened.
            tap("‹")
            XCTAssertTrue(waitFor("PLAY").exists, "Did not return to the menu from \(destination)")
        }
    }
}

/// Mirrors `GameMode.selectable.count` without importing the app module, which
/// a UI test target cannot do.
private enum GameMode {
    static let selectableCount = 6
}
