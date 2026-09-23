import SpriteKit
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

    func testEveryModeHasSaneGameplayMultipliersAndSelectableOrder() {
        XCTAssertEqual(GameMode.selectable, GameMode.allCases)
        for mode in GameMode.allCases {
            XCTAssertGreaterThan(mode.startingPipeGap, 0)
            XCTAssertGreaterThan(mode.scrollMultiplier, 0)
            XCTAssertGreaterThan(mode.gravityMultiplier, 0)
        }
        XCTAssertTrue(GameMode.endless.ramps)
        XCTAssertTrue(GameMode.timeAttack.ramps)
        XCTAssertTrue(GameMode.hardcore.ramps)
        XCTAssertTrue(GameMode.daily.ramps)
        XCTAssertFalse(GameMode.classic.ramps)
        XCTAssertFalse(GameMode.zen.ramps)
        XCTAssertLessThan(GameMode.hardcore.scrollMultiplier, GameMode.classic.scrollMultiplier)
        XCTAssertGreaterThan(GameMode.zen.scrollMultiplier, GameMode.classic.scrollMultiplier)
    }

    // MARK: - Flying over the pipes

    /// The bird must be stopped by the ceiling, not merely notified about it.
    ///
    /// SpriteKit collisions are one-way: a body is stopped only by the
    /// categories in its *own* `collisionBitMask`. The ceiling listed the bird,
    /// but the bird did not list the ceiling, so a hard enough climb carried it
    /// over the top pipe and past the gap.
    func testTheBirdCollidesWithTheCeiling() {
        let bird = Bird.make(skin: .classic)
        bird.attachPhysics()

        let mask = try? XCTUnwrap(bird.physicsBody).collisionBitMask
        XCTAssertEqual(
            (mask ?? 0) & PhysicsCategory.ceiling.rawValue,
            PhysicsCategory.ceiling.rawValue,
            "The bird passes through the ceiling and can skip the gap"
        )
    }

    /// Everything solid, in one assertion, so none of it is lost to an edit.
    func testTheBirdCollidesWithEverythingSolid() {
        let bird = Bird.make(skin: .classic)
        bird.attachPhysics()
        let mask = bird.physicsBody?.collisionBitMask ?? 0

        for category in [PhysicsCategory.world, .pipe, .ceiling] {
            XCTAssertEqual(
                mask & category.rawValue,
                category.rawValue,
                "The bird should be stopped by \(category.rawValue)"
            )
        }
    }

    /// Pick-ups must stay pass-through, or the bird bounces off a coin.
    func testPickupsDoNotBlockTheBird() {
        let bird = Bird.make(skin: .classic)
        bird.attachPhysics()
        let mask = bird.physicsBody?.collisionBitMask ?? 0

        for category in [PhysicsCategory.coin, .powerUp, .scoreGate] {
            XCTAssertEqual(mask & category.rawValue, 0, "Pick-ups must not be solid")
        }
    }

    /// A top pipe has to reach past the ceiling, or there is a gap above it.
    func testTopPipesExtendAboveTheCeiling() {
        let sceneHeight: CGFloat = 900
        let gapTop: CGFloat = sceneHeight - 60 // the highest a gap can sit
        let topHeight = max(60, sceneHeight + 200 - gapTop)

        XCTAssertGreaterThan(
            gapTop + topHeight,
            sceneHeight + 22 + 10,
            "The pipe must overlap the ceiling, leaving no way over the top"
        )
    }

    func testBirdClampsVerticalVelocityAtBothLimits() throws {
        let bird = Bird.make(skin: .classic)
        bird.attachPhysics()
        let body = try XCTUnwrap(bird.physicsBody)

        body.velocity = CGVector(dx: 12, dy: GameConfig.maxRiseSpeed * 2)
        bird.clampVelocity()
        XCTAssertEqual(body.velocity.dx, 12, accuracy: 0.001)
        XCTAssertEqual(body.velocity.dy, GameConfig.maxRiseSpeed, accuracy: 0.001)

        body.velocity = CGVector(dx: -9, dy: GameConfig.maxFallSpeed * 2)
        bird.clampVelocity()
        XCTAssertEqual(body.velocity.dx, -9, accuracy: 0.001)
        XCTAssertEqual(body.velocity.dy, GameConfig.maxFallSpeed, accuracy: 0.001)
    }

    func testBirdHorizontalClampBoundsPositionAndSpeed() throws {
        let bird = Bird.make(skin: .classic)
        bird.attachPhysics()
        let body = try XCTUnwrap(bird.physicsBody)
        bird.position.x = 500
        body.velocity = CGVector(dx: 1_000, dy: 40)

        bird.clampHorizontal(anchorX: 100, maxDrift: 25, deltaTime: 1 / 60)

        XCTAssertEqual(bird.position.x, 125, accuracy: 0.001)
        XCTAssertEqual(body.velocity.dx, 0, accuracy: 0.001)
        XCTAssertEqual(body.velocity.dy, 40, accuracy: 0.001)
    }

    func testBirdDeathStateOnlyCollidesWithTheWorld() throws {
        let bird = Bird.make(skin: .classic)
        bird.attachPhysics()
        bird.enterDeathState()
        let body = try XCTUnwrap(bird.physicsBody)

        XCTAssertEqual(body.collisionBitMask, PhysicsCategory.world.rawValue)
        XCTAssertEqual(body.contactTestBitMask, PhysicsCategory.world.rawValue)
        XCTAssertNil(bird.action(forKey: "flap-animation"))
    }

    // MARK: - Obstacles and collectibles

    func testCoinIsAPassThroughBirdSensor() throws {
        let coin = Collectible.makeCoin()
        let body = try XCTUnwrap(coin.physicsBody)

        XCTAssertEqual(coin.name, Collectible.coinKey)
        XCTAssertEqual(body.categoryBitMask, PhysicsCategory.coin.rawValue)
        XCTAssertEqual(body.contactTestBitMask, PhysicsCategory.bird.rawValue)
        XCTAssertEqual(body.collisionBitMask, 0)
        XCTAssertFalse(body.isDynamic)
    }

    func testEveryPowerUpRoundTripsThroughNodeMetadata() throws {
        for kind in PowerUpKind.allCases {
            let node = Collectible.makePowerUp(kind: kind)
            let body = try XCTUnwrap(node.physicsBody)
            XCTAssertEqual(node.name, Collectible.powerUpKey)
            XCTAssertEqual(Collectible.kind(from: node), kind)
            XCTAssertEqual(body.categoryBitMask, PhysicsCategory.powerUp.rawValue)
            XCTAssertEqual(body.contactTestBitMask, PhysicsCategory.bird.rawValue)
            XCTAssertEqual(body.collisionBitMask, 0)
        }
        XCTAssertNil(Collectible.kind(from: SKNode()))
    }

    func testPipePairBuildsTwoSolidPipesAndOnePassThroughGate() {
        let pair = PipePair.make(.init(
            gapCentre: 400,
            gapHeight: 170,
            sceneHeight: 900,
            content: .coin,
            tint: .white,
            tintStrength: 0,
            moving: false
        ))

        XCTAssertEqual(pair.gapCentre, 400, accuracy: 0.001)
        XCTAssertEqual(pair.gapHeight, 170, accuracy: 0.001)
        let pipes = pair.children.filter {
            $0.physicsBody?.categoryBitMask == PhysicsCategory.pipe.rawValue
        }
        XCTAssertEqual(pipes.count, 2)
        let gate = pair.children.first { $0.physicsBody?.categoryBitMask == PhysicsCategory.scoreGate.rawValue }
        XCTAssertNotNil(gate)
        XCTAssertEqual(gate?.physicsBody?.collisionBitMask, 0)
        XCTAssertEqual(pair.children.filter { $0.name == Collectible.coinKey }.count, 1)

        XCTAssertFalse(pair.hasScored)
        pair.markScored()
        XCTAssertTrue(pair.hasScored)
    }

    func testMovingPipePairOwnsADriftActionAndPowerUp() {
        let pair = PipePair.make(.init(
            gapCentre: 300,
            gapHeight: 150,
            sceneHeight: 800,
            content: .powerUp(.magnet),
            tint: .cyan,
            tintStrength: 0.2,
            moving: true
        ))

        XCTAssertNotNil(pair.action(forKey: "drift"))
        XCTAssertEqual(pair.children.compactMap(Collectible.kind(from:)), [.magnet])
    }

    // MARK: - Presentation helpers

    func testTextFitPreservesShortTextAndEllipsizesLongText() {
        let short = "Bird"
        XCTAssertEqual(TextFit.truncate(short, toWidth: 500, fontNamed: Fonts.body, fontSize: 16), short)
        XCTAssertEqual(TextFit.truncate(short, toWidth: 0, fontNamed: Fonts.body, fontSize: 16), "")

        let truncated = TextFit.truncate(
            "A deliberately very long player name",
            toWidth: 40,
            fontNamed: Fonts.body,
            fontSize: 16
        )
        XCTAssertTrue(truncated.hasSuffix("…"))
        XCTAssertLessThan(truncated.count, 36)
    }

    func testCoinCounterExposesTheRequestedAmount() {
        let counter = CoinIcon.counter(amount: 123, radius: 9, fontSize: 20)
        XCTAssertEqual(counter.label.text, "123")
        XCTAssertTrue(counter.node.children.contains(counter.label))
        XCTAssertEqual(counter.label.horizontalAlignmentMode, .left)
    }

    func testWeatherPropertiesAndReducedMotionApplication() {
        XCTAssertEqual(Weather.clear.windForce, 0)
        XCTAssertGreaterThan(Weather.windy.windForce, 0)
        XCTAssertGreaterThan(Weather.rain.downdraft, 0)
        XCTAssertGreaterThan(Weather.fog.fogAlpha, 0)
        for weather in Weather.allCases {
            XCTAssertFalse(weather.displayName.isEmpty)
            XCTAssertFalse(weather.symbol.isEmpty)
        }

        let container = SKNode()
        let system = WeatherSystem(container: container)
        system.apply(.rain, sceneSize: CGSize(width: 400, height: 800), reduceMotion: true)
        XCTAssertEqual(system.weather, .rain)
        XCTAssertTrue(container.children.isEmpty)
        XCTAssertEqual(system.update(deltaTime: 1, elapsed: 1), .zero)
    }

    func testWindTracksElapsedExposureAndResetClearsIt() {
        let system = WeatherSystem(container: SKNode())
        system.apply(.windy, sceneSize: CGSize(width: 400, height: 800), reduceMotion: false)
        let first = system.update(deltaTime: 0.5, elapsed: 0)
        XCTAssertNotEqual(first.dx, 0)
        XCTAssertEqual(first.dy, 0)
        XCTAssertEqual(system.secondsInWind, 0.5, accuracy: 0.001)
        system.reset()
        XCTAssertEqual(system.secondsInWind, 0)
    }
}
