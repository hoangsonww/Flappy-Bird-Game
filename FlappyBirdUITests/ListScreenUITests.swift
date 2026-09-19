import XCTest

/// Leaderboard, achievements and stats — every filter chip on every screen.
final class ListScreenUITests: GameUITestCase {

    private func checkSegments(screen: String, segments: [String]) {
        launch(screen: screen)
        for segment in segments {
            tap(segment)
            // The chip staying put is the contract: switching filters must not
            // tear down the screen or leave it without a way back.
            XCTAssertTrue(control(segment).exists, "\(screen): \(segment) vanished after being tapped")
            XCTAssertTrue(control("‹").exists, "\(screen): lost the back button on \(segment)")
            capture("\(screen)-\(segment.lowercased().replacingOccurrences(of: " ", with: "-"))")
        }
        tap("‹")
        XCTAssertTrue(waitFor("PLAY").exists, "\(screen) did not return to the menu")
    }

    func testLeaderboardWindows() {
        checkSegments(screen: "leaderboard", segments: ["ALL TIME", "TODAY", "WEEK", "MONTH"])
    }

    func testAchievementFilters() {
        checkSegments(screen: "achievements", segments: ["ALL", "UNLOCKED", "LOCKED"])
    }

    func testStatsSegments() {
        checkSegments(screen: "stats", segments: ["TOTALS", "BY MODE", "RECENT"])
    }

    /// Seeded runs have to show up somewhere, or the screen is lying.
    func testStatsShowsSeededProgress() {
        launch(screen: "stats")
        let labels = app.staticTexts.allElementsBoundByIndex.map(\.label)
        XCTAssertTrue(
            labels.contains { $0.contains("Games played") },
            "Stats has no totals. On screen: \(labels)"
        )
    }
}
