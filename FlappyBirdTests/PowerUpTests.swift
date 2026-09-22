import XCTest
@testable import FlappyBird

/// Power-up activation, expiry, stacking and shield charges.
final class PowerUpTests: XCTestCase {

    func testTimedPowerUpExpires() {
        var active = ActivePowerUps()
        active.activate(.magnet, now: 0)

        XCTAssertTrue(active.isActive(.magnet, now: 1))
        XCTAssertTrue(active.isActive(.magnet, now: GameConfig.magnetDuration - 0.1))
        XCTAssertFalse(active.isActive(.magnet, now: GameConfig.magnetDuration + 0.1))
    }

    func testReCollectingExtendsRatherThanReplaces() {
        var active = ActivePowerUps()
        active.activate(.doublePoints, now: 0)
        active.activate(.doublePoints, now: 2)

        let expectedEnd = GameConfig.doublePointsDuration * 2
        XCTAssertTrue(active.isActive(.doublePoints, now: expectedEnd - 1))
        XCTAssertEqual(active.remaining(.doublePoints, now: 0), expectedEnd, accuracy: 0.001)
    }

    func testShieldIsChargeBasedNotTimeBased() {
        var active = ActivePowerUps()
        XCTAssertFalse(active.hasShield)

        active.activate(.shield, now: 0)
        XCTAssertTrue(active.hasShield)
        XCTAssertTrue(active.isActive(.shield, now: 9_999), "A shield never times out")

        XCTAssertTrue(active.consumeShield())
        XCTAssertFalse(active.hasShield)
        XCTAssertFalse(active.consumeShield(), "Only one hit per charge")
    }

    func testShieldChargesAreCapped() {
        var active = ActivePowerUps()
        for _ in 0..<5 { active.activate(.shield, now: 0) }

        XCTAssertTrue(active.consumeShield())
        XCTAssertTrue(active.consumeShield())
        XCTAssertFalse(active.consumeShield(), "At most two charges can be banked")
    }

    func testCollectionCountTracksEveryPickup() {
        var active = ActivePowerUps()
        active.activate(.magnet, now: 0)
        active.activate(.shield, now: 0)
        active.activate(.shrink, now: 0)

        XCTAssertEqual(active.totalCollected, 3)
    }

    func testExpireDropsFinishedEffectsOnly() {
        var active = ActivePowerUps()
        active.activate(.slowMotion, now: 0)
        active.activate(.magnet, now: 0)

        active.expire(now: GameConfig.slowMotionDuration + 0.1)

        XCTAssertFalse(active.isActive(.slowMotion, now: GameConfig.slowMotionDuration + 0.1))
        XCTAssertTrue(active.isActive(.magnet, now: GameConfig.slowMotionDuration + 0.1))
    }

    func testActiveKindsIncludeTheShieldAndAreStable() {
        var active = ActivePowerUps()
        active.activate(.shield, now: 0)
        active.activate(.magnet, now: 0)

        let kinds = active.activeKinds(now: 1)
        XCTAssertEqual(kinds, kinds.sorted { $0.rawValue < $1.rawValue }, "Badge order must not jitter")
        XCTAssertTrue(kinds.contains(.shield))
        XCTAssertTrue(kinds.contains(.magnet))
    }

    func testResetClearsEverything() {
        var active = ActivePowerUps()
        active.activate(.shield, now: 0)
        active.activate(.magnet, now: 0)
        active.reset()

        XCTAssertFalse(active.hasShield)
        XCTAssertFalse(active.isActive(.magnet, now: 0))
        XCTAssertEqual(active.totalCollected, 0)
    }

    func testRandomSelectionIsSeededAndCoversEveryKind() {
        var first = SeededRandom(seed: 2_024)
        var second = SeededRandom(seed: 2_024)
        XCTAssertEqual(
            PowerUpKind.random(using: &first),
            PowerUpKind.random(using: &second),
            "Daily challenges depend on reproducible pickups"
        )

        var generator = SeededRandom(seed: 5)
        var seen = Set<PowerUpKind>()
        for _ in 0..<500 { seen.insert(PowerUpKind.random(using: &generator)) }
        XCTAssertEqual(seen.count, PowerUpKind.allCases.count)
    }

    func testOnlyTheShieldHasNoDuration() {
        for kind in PowerUpKind.allCases {
            if kind == .shield {
                XCTAssertNil(kind.duration)
            } else {
                XCTAssertNotNil(kind.duration, "\(kind) needs a duration")
                XCTAssertGreaterThan(kind.duration ?? 0, 0)
            }
            XCTAssertGreaterThan(kind.weight, 0)
            XCTAssertFalse(kind.displayName.isEmpty)
        }
    }
}
