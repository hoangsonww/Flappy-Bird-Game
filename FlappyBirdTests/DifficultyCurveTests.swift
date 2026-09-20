import XCTest
@testable import FlappyBird

/// The difficulty curve has to stay bounded: a great run should be hard, never
/// impossible, and a non-ramping mode should never change at all.
final class DifficultyCurveTests: XCTestCase {

    func testClassicModeNeverRamps() {
        let curve = DifficultyCurve(mode: .classic)
        let start = curve.snapshot(pipesPassed: 0)
        let late = curve.snapshot(pipesPassed: 500)

        XCTAssertEqual(start.pipeGap, late.pipeGap)
        XCTAssertEqual(start.spawnInterval, late.spawnInterval)
        XCTAssertEqual(start.scrollRate, late.scrollRate)
        XCTAssertEqual(curve.progress(pipesPassed: 500), 0)
    }

    func testEndlessModeTightensGapsAndSpeedsUp() {
        let curve = DifficultyCurve(mode: .endless)
        let start = curve.snapshot(pipesPassed: 0)
        let late = curve.snapshot(pipesPassed: 60)

        XCTAssertLessThan(late.pipeGap, start.pipeGap, "Gaps should narrow")
        XCTAssertLessThan(late.spawnInterval, start.spawnInterval, "Pipes should arrive sooner")
        XCTAssertLessThan(late.scrollRate, start.scrollRate, "Scrolling should get faster")
    }

    func testProgressIsMonotonicAndClamped() {
        let curve = DifficultyCurve(mode: .endless)
        var previous: CGFloat = -1

        for pipes in stride(from: 0, through: 200, by: 5) {
            let progress = curve.progress(pipesPassed: pipes)
            XCTAssertGreaterThanOrEqual(progress, previous)
            XCTAssertGreaterThanOrEqual(progress, 0)
            XCTAssertLessThanOrEqual(progress, 1)
            previous = progress
        }
        XCTAssertEqual(curve.progress(pipesPassed: 1_000), 1, accuracy: 0.0001)
    }

    func testNegativePipeCountIsTreatedAsTheStart() {
        let curve = DifficultyCurve(mode: .endless)
        XCTAssertEqual(curve.progress(pipesPassed: -10), 0)
    }

    func testGapNeverFallsBelowTheConfiguredFloor() {
        for mode in GameMode.allCases {
            let curve = DifficultyCurve(mode: mode)
            for pipes in [0, 25, 40, 100, 1_000] {
                let snapshot = curve.snapshot(pipesPassed: pipes)
                XCTAssertGreaterThanOrEqual(
                    snapshot.pipeGap,
                    GameConfig.minimumVerticalPipeGap,
                    "\(mode) at \(pipes) pipes produced an impossible gap"
                )
                XCTAssertGreaterThanOrEqual(snapshot.spawnInterval, GameConfig.minimumSpawnInterval)
                XCTAssertGreaterThan(snapshot.scrollRate, 0)
            }
        }
    }

    func testDailyChallengeOverridesTheStartingGap() {
        let curve = DifficultyCurve(mode: .daily, pipeGapOverride: 118, gravityScale: 1.1, speedScale: 1.2)
        let snapshot = curve.snapshot(pipesPassed: 0)

        XCTAssertEqual(snapshot.pipeGap, 118)
        XCTAssertEqual(
            snapshot.gravity,
            GameConfig.gravity * GameMode.daily.gravityMultiplier * 1.1,
            accuracy: 0.001
        )
    }

    func testHigherSpeedScaleMakesTheWorldScrollFaster() {
        let normal = DifficultyCurve(mode: .daily, speedScale: 1.0).snapshot(pipesPassed: 0)
        let fast = DifficultyCurve(mode: .daily, speedScale: 1.3).snapshot(pipesPassed: 0)
        XCTAssertLessThan(fast.scrollRate, normal.scrollRate)
    }

    func testHardcoreGravityIsStrongerThanClassic() {
        let classic = DifficultyCurve(mode: .classic).snapshot(pipesPassed: 0)
        let hardcore = DifficultyCurve(mode: .hardcore).snapshot(pipesPassed: 0)
        XCTAssertLessThan(hardcore.gravity, classic.gravity, "Gravity is negative, so stronger is lower")
    }

    /// The reaction window is the thing that decides whether the game is fair:
    /// the seconds between one gap and the next, whatever the scroll speed.
    func testEveryModeKeepsAUsableReactionWindow() {
        for mode in GameMode.allCases {
            for pipes in [0, 10, 40, 200, 2_000] {
                let snapshot = DifficultyCurve(mode: mode).snapshot(pipesPassed: pipes)
                XCTAssertGreaterThanOrEqual(
                    snapshot.spawnInterval,
                    GameConfig.minimumSpawnInterval,
                    "\(mode) at \(pipes) pipes drops below the floor"
                )
                XCTAssertGreaterThanOrEqual(
                    snapshot.spawnInterval,
                    1.2,
                    "\(mode) at \(pipes) pipes leaves too little time to react"
                )
            }
        }
    }

    /// Pitch in points, which is what the spacing actually looks like on screen.
    func testPipesAreNeverPackedTooCloselyTogether() {
        // One pipe is 60pt wide, so this leaves at least ~125pt of clear air.
        let floor: CGFloat = 185

        for mode in GameMode.allCases {
            for pipes in [0, 10, 40, 200, 2_000] {
                let snapshot = DifficultyCurve(mode: mode).snapshot(pipesPassed: pipes)
                XCTAssertGreaterThanOrEqual(
                    snapshot.horizontalSpacing,
                    floor,
                    "\(mode) at \(pipes) pipes spaces pipes only \(snapshot.horizontalSpacing)pt apart"
                )
            }
        }
    }

    /// A daily challenge may speed the world up; it must not close the window.
    func testASpedUpDailyStillKeepsItsWindow() {
        let curve = DifficultyCurve(mode: .daily, gravityScale: 1.15, speedScale: 1.25)
        let late = curve.snapshot(pipesPassed: 200)

        XCTAssertGreaterThanOrEqual(late.spawnInterval, GameConfig.minimumSpawnInterval)
        XCTAssertGreaterThanOrEqual(late.horizontalSpacing, 185)
    }

    func testLevelClimbsWithProgress() {
        let curve = DifficultyCurve(mode: .endless)
        XCTAssertEqual(curve.level(pipesPassed: 0), 1)
        XCTAssertGreaterThan(curve.level(pipesPassed: 60), curve.level(pipesPassed: 5))
        XCTAssertLessThanOrEqual(curve.level(pipesPassed: 10_000), 6)
    }
}
