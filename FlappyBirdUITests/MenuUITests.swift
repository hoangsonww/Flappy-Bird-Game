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

        let start = waitForModeName()
        tap("▶")
        let advanced = waitForModeName(otherThan: start)
        XCTAssertNotEqual(advanced, start, "The right arrow did not change the mode")

        tap("◀")
        XCTAssertEqual(waitForModeName(otherThan: advanced), start, "Cycling back did not restore the mode")
    }

    /// The mode name on the card, once one is published.
    ///
    /// Pass `otherThan` after tapping an arrow: the label is repainted a frame
    /// or two later, so reading once can return the mode that was showing
    /// before the tap.
    private func waitForModeName(otherThan previous: String? = nil, file: StaticString = #filePath, line: UInt = #line) -> String {
        let modes = ["CLASSIC", "ENDLESS", "TIME ATTACK", "HARDCORE", "ZEN", "DAILY"]
        func nameOn(_ labels: [String]) -> String? {
            labels.first { label in modes.contains { label.contains($0) } }
        }

        let labels = waitForLabels("a mode name on the card") { labels in
            guard let name = nameOn(labels) else { return false }
            return name != previous
        }
        guard let name = nameOn(labels) else {
            XCTFail("No mode name on the card. On screen: \(labels)", file: file, line: line)
            return ""
        }
        return name
    }

    func testEveryModeIsReachableAndKeepsItsLayout() {
        launch()
        let play = waitFor("PLAY")

        // One full lap of the selector. Each stop must keep its labels inside
        // the card — long subtitles used to run underneath the arrows.
        var previous = waitForModeName()
        for step in 0..<GameMode.selectableCount {
            tap("▶")
            previous = waitForModeName(otherThan: previous)
            // SpriteKit publishes its labels as `.other`, not `.staticText` —
            // `app.staticTexts` matches nothing in this app, which is why the
            // loop this replaces never actually ran. Filtering by type also
            // drops the application element, which is the full screen width.
            let texts = snapshotElements().filter {
                $0.elementType == .other && $0.frame.width > 0 && !$0.label.isEmpty
            }
            XCTAssertFalse(texts.isEmpty, "Step \(step) left the card blank")
            for element in texts {
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
