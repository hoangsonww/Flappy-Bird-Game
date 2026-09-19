import XCTest

@testable import FlappyBird

/// Unlock evaluation, including the client-only "special" achievements.
final class AchievementSystemTests: XCTestCase {

    private var store: GameStore!
    private var system: AchievementSystem!

    override func setUp() {
        super.setUp()
        store = TestSupport.makeStore()
        system = AchievementSystem(store: store)
    }

    func testCatalogIntegrity() {
        XCTAssertEqual(
            Set(AchievementCatalog.all.map(\.code)).count,
            AchievementCatalog.all.count,
            "Codes must be unique — they are the sync key"
        )
        XCTAssertGreaterThan(AchievementCatalog.totalPoints, 0)

        for achievement in AchievementCatalog.all {
            XCTAssertFalse(achievement.name.isEmpty)
            XCTAssertFalse(achievement.detail.isEmpty)
            XCTAssertFalse(achievement.icon.isEmpty)
            XCTAssertGreaterThan(achievement.threshold, 0)
            XCTAssertGreaterThan(achievement.points, 0)
        }
    }

    func testDefinitionLookup() {
        XCTAssertEqual(AchievementCatalog.definition(for: "century")?.threshold, 100)
        XCTAssertNil(AchievementCatalog.definition(for: "not_a_code"))
    }

    func testScoreThresholdsUnlockInOrder() {
        _ = store.record(run: TestSupport.run(score: 27), mode: .classic, deathCause: .pipe)
        let unlocked = system.evaluate(run: TestSupport.run(score: 27), mode: .classic).map(\.code)

        XCTAssertTrue(unlocked.contains("first_flight"))
        XCTAssertTrue(unlocked.contains("getting_warm"))
        XCTAssertTrue(unlocked.contains("sky_rookie"))
        XCTAssertFalse(unlocked.contains("pipe_dreamer"), "50 is still out of reach")
    }

    func testAchievementsAreReportedOnlyOnce() {
        _ = store.record(run: TestSupport.run(score: 12), mode: .classic, deathCause: .pipe)
        let first = system.evaluate(run: TestSupport.run(score: 12), mode: .classic)
        XCTAssertFalse(first.isEmpty)

        _ = store.record(run: TestSupport.run(score: 13), mode: .classic, deathCause: .pipe)
        let second = system.evaluate(run: TestSupport.run(score: 13), mode: .classic)
        XCTAssertTrue(second.isEmpty, "Already-earned achievements must not re-toast")
    }

    func testCoinAndGameMetricsUseLifetimeTotals() {
        for _ in 0..<50 {
            _ = store.record(run: TestSupport.run(score: 2, coins: 3), mode: .classic, deathCause: .pipe)
        }
        let unlocked = system.evaluate(run: TestSupport.run(score: 2, coins: 3), mode: .classic).map(\.code)

        XCTAssertTrue(unlocked.contains("coin_collector"), "150 coins collected in total")
        XCTAssertTrue(unlocked.contains("persistent"), "50 games played")
    }

    func testNightOwlNeedsANightRun() {
        var unlocked = system.evaluate(run: TestSupport.run(score: 5), mode: .classic).map(\.code)
        XCTAssertFalse(unlocked.contains("night_owl"))

        unlocked = system.evaluate(run: TestSupport.run(score: 5, sawNight: true), mode: .classic).map(\.code)
        XCTAssertTrue(unlocked.contains("night_owl"))
    }

    func testStormChaserNeedsThirtySecondsOfWind() {
        var unlocked = system.evaluate(
            run: TestSupport.run(score: 5, windSeconds: 12),
            mode: .classic
        ).map(\.code)
        XCTAssertFalse(unlocked.contains("storm_chaser"))

        unlocked = system.evaluate(
            run: TestSupport.run(score: 5, windSeconds: 31),
            mode: .classic
        ).map(\.code)
        XCTAssertTrue(unlocked.contains("storm_chaser"))
    }

    func testPerfectStartRequiresNoPowerUps() {
        var unlocked = system.evaluate(
            run: TestSupport.run(score: 12, powerUps: 1),
            mode: .classic
        ).map(\.code)
        XCTAssertFalse(unlocked.contains("perfect_start"))

        unlocked = system.evaluate(
            run: TestSupport.run(score: 12, powerUps: 0),
            mode: .classic
        ).map(\.code)
        XCTAssertTrue(unlocked.contains("perfect_start"))
    }

    func testGhostRiderIsSecretAndNeedsTheGhostBeaten() {
        let definition = AchievementCatalog.definition(for: "ghost_rider")
        XCTAssertEqual(definition?.secret, true)

        let unlocked = system.evaluate(
            run: TestSupport.run(score: 30, beatGhost: true),
            mode: .classic
        ).map(\.code)
        XCTAssertTrue(unlocked.contains("ghost_rider"))
    }

    func testDailyDevoteeCountsCompletedChallenges() {
        for day in 1...7 {
            store.markDailyCompleted(String(format: "2026-03-%02d", day))
        }
        let unlocked = system.evaluate(run: TestSupport.run(score: 3), mode: .daily).map(\.code)
        XCTAssertTrue(unlocked.contains("daily_devotee"))
    }

    func testSyncPayloadOnlyContainsKnownCodes() {
        store.setProgress(5, unlocked: true, for: "first_flight")
        store.setProgress(3, unlocked: false, for: "definitely_not_real")

        let payload = system.syncPayload()
        let codes = payload.compactMap { $0["code"] as? String }

        XCTAssertTrue(codes.contains("first_flight"))
        XCTAssertFalse(codes.contains("definitely_not_real"), "Unknown codes would be rejected by the API")
    }

    func testSyncPayloadIncludesUnlockTimestamps() {
        store.setProgress(1, unlocked: true, for: "first_flight")
        let entry = system.syncPayload().first { $0["code"] as? String == "first_flight" }

        XCTAssertNotNil(entry?["unlockedAt"] as? String)
    }
}
