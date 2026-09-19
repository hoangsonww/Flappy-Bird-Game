import XCTest

@testable import FlappyBird

/// Medals, physics categories, run bookkeeping and mode rules.
final class CoreModelTests: XCTestCase {

    // MARK: - Medals

    func testMedalThresholdsAreOrdered() {
        let thresholds = Medal.allCases.map(\.threshold)
        XCTAssertEqual(thresholds, thresholds.sorted(), "Medal thresholds must ascend")
    }

    func testMedalEarnedPicksHighestTierReached() {
        XCTAssertEqual(Medal.earned(for: 0), .none)
        XCTAssertEqual(Medal.earned(for: 9), .none)
        XCTAssertEqual(Medal.earned(for: 10), .bronze)
        XCTAssertEqual(Medal.earned(for: 24), .bronze)
        XCTAssertEqual(Medal.earned(for: 25), .silver)
        XCTAssertEqual(Medal.earned(for: 99), .gold)
        XCTAssertEqual(Medal.earned(for: 100), .platinum)
        XCTAssertEqual(Medal.earned(for: 10_000), .platinum)
    }

    // MARK: - Physics categories

    func testPhysicsCategoriesAreDistinctBits() {
        let all: [PhysicsCategory] = [
            .bird, .world, .pipe, .scoreGate, .coin, .powerUp, .ceiling,
        ]
        let combined = all.reduce(into: UInt32(0)) { $0 |= $1.rawValue }
        XCTAssertEqual(combined.nonzeroBitCount, all.count, "Each category needs its own bit")
    }

    func testCategoryUnionContainsMembers() {
        let mask = PhysicsCategory.world.union(.pipe)
        XCTAssertTrue(mask.contains(.pipe))
        XCTAssertTrue(mask.contains(.world))
        XCTAssertFalse(mask.contains(.coin))
    }

    // MARK: - Run stats

    func testComboMultiplierStartsAtOneAndIsCapped() {
        var stats = RunStats()
        XCTAssertEqual(stats.comboMultiplier, 1, "No combo still awards the base value")

        stats.combo = 3
        XCTAssertEqual(stats.comboMultiplier, 3)

        stats.combo = 999
        XCTAssertEqual(stats.comboMultiplier, GameConfig.maxComboMultiplier)
    }

    func testCollectingCoinsGrowsComboAndTracksBest() {
        var stats = RunStats()
        stats.registerCoin()
        stats.registerCoin()
        stats.registerCoin()

        XCTAssertEqual(stats.combo, 3)
        XCTAssertEqual(stats.maxCombo, 3)
        // Coin value is multiplied by the combo at the moment of pickup: 1 + 2 + 3.
        XCTAssertEqual(stats.coins, 6)

        stats.breakCombo()
        XCTAssertEqual(stats.combo, 0)
        XCTAssertEqual(stats.maxCombo, 3, "Breaking a combo keeps the best")

        stats.registerCoin()
        XCTAssertEqual(stats.coins, 7, "A fresh combo is back to a x1 multiplier")
    }

    func testDurationUsesEndTimestampWhenPresent() {
        var stats = RunStats()
        stats.startedAt = Date(timeIntervalSince1970: 100)
        stats.endedAt = Date(timeIntervalSince1970: 142.5)

        XCTAssertEqual(stats.duration, 42.5, accuracy: 0.001)
        XCTAssertEqual(stats.durationMs, 42_500)
    }

    // MARK: - Game state

    func testStateGatesInput() {
        XCTAssertTrue(GameState.ready.acceptsFlap)
        XCTAssertTrue(GameState.playing.acceptsFlap)
        XCTAssertFalse(GameState.paused.acceptsFlap)
        XCTAssertFalse(GameState.dying.acceptsFlap)
        XCTAssertFalse(GameState.gameOver.acceptsFlap)

        XCTAssertTrue(GameState.paused.showsOverlay)
        XCTAssertTrue(GameState.gameOver.showsOverlay)
        XCTAssertFalse(GameState.playing.showsOverlay)
    }

    // MARK: - Modes

    func testZenModeIsNeitherLethalNorRanked() {
        XCTAssertFalse(GameMode.zen.isLethal, "Zen exists to practise without dying")
        XCTAssertFalse(GameMode.zen.isRanked, "Zen scores would distort the leaderboards")

        for mode in GameMode.allCases where mode != .zen {
            XCTAssertTrue(mode.isLethal, "\(mode) should end on contact")
            XCTAssertTrue(mode.isRanked, "\(mode) should be submittable")
        }
    }

    func testHardcoreAndDailyDisablePowerUps() {
        XCTAssertFalse(GameMode.hardcore.allowsPowerUps)
        XCTAssertFalse(GameMode.daily.allowsPowerUps, "Everyone must play the same layout")
        XCTAssertTrue(GameMode.classic.allowsPowerUps)
    }

    func testOnlyTimeAttackHasATimeLimit() {
        XCTAssertEqual(GameMode.timeAttack.timeLimit, GameConfig.timeAttackDuration)
        for mode in GameMode.allCases where mode != .timeAttack {
            XCTAssertNil(mode.timeLimit)
        }
    }

    func testHardcoreStartsTighterThanClassic() {
        XCTAssertLessThan(GameMode.hardcore.startingPipeGap, GameMode.classic.startingPipeGap)
        XCTAssertGreaterThan(GameMode.zen.startingPipeGap, GameMode.classic.startingPipeGap)
    }

    func testEveryModeRawValueMatchesTheBackendContract() {
        // These strings are the API contract; renaming one breaks score submission.
        XCTAssertEqual(
            Set(GameMode.allCases.map(\.rawValue)),
            ["classic", "endless", "timeAttack", "hardcore", "zen", "daily"]
        )
    }

    func testEveryModeHasCopyForTheMenu() {
        for mode in GameMode.allCases {
            XCTAssertFalse(mode.displayName.isEmpty)
            XCTAssertFalse(mode.subtitle.isEmpty)
            XCTAssertFalse(mode.symbol.isEmpty)
        }
    }
}
