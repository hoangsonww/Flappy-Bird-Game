import XCTest

@testable import FlappyBird

/// `GameStore` and `Settings` — the only things that survive an app restart.
final class PersistenceTests: XCTestCase {

    private var store: GameStore!

    override func setUp() {
        super.setUp()
        store = TestSupport.makeStore()
    }

    // MARK: - Runs

    func testRecordingARunUpdatesBestScoreAndStats() {
        let isBest = store.record(run: TestSupport.run(score: 25, coins: 8, combo: 4), mode: .classic, deathCause: .pipe)

        XCTAssertTrue(isBest)
        XCTAssertEqual(store.profile.bestScore(for: .classic), 25)
        XCTAssertEqual(store.profile.stats.gamesPlayed, 1)
        XCTAssertEqual(store.profile.stats.totalCoins, 8)
        XCTAssertEqual(store.profile.stats.bestCombo, 4)
        XCTAssertEqual(store.profile.stats.deathsByPipe, 1)
        XCTAssertEqual(store.profile.wallet, 8, "Coins earned go into the wallet")
    }

    func testLowerScoreIsNotAPersonalBest() {
        _ = store.record(run: TestSupport.run(score: 30), mode: .classic, deathCause: .pipe)
        let isBest = store.record(run: TestSupport.run(score: 12), mode: .classic, deathCause: .ground)

        XCTAssertFalse(isBest)
        XCTAssertEqual(store.profile.bestScore(for: .classic), 30)
        XCTAssertEqual(store.profile.stats.deathsByGround, 1)
    }

    func testBestScoresAreTrackedPerMode() {
        _ = store.record(run: TestSupport.run(score: 40), mode: .classic, deathCause: .pipe)
        _ = store.record(run: TestSupport.run(score: 9), mode: .hardcore, deathCause: .pipe)

        XCTAssertEqual(store.profile.bestScore(for: .classic), 40)
        XCTAssertEqual(store.profile.bestScore(for: .hardcore), 9)
        XCTAssertEqual(store.profile.bestScore(for: .endless), 0)
        XCTAssertEqual(store.profile.overallBest, 40)
    }

    func testZenRunsAreNeverQueuedForUpload() {
        _ = store.record(run: TestSupport.run(score: 15), mode: .zen, deathCause: .none)
        XCTAssertTrue(store.profile.pendingUploads.isEmpty, "Zen is local practice")

        _ = store.record(run: TestSupport.run(score: 15), mode: .classic, deathCause: .pipe)
        XCTAssertEqual(store.profile.pendingUploads.count, 1)
    }

    func testMarkUploadedRemovesMatchingRuns() {
        _ = store.record(run: TestSupport.run(score: 11), mode: .classic, deathCause: .pipe)
        let queued = store.profile.pendingUploads
        XCTAssertEqual(queued.count, 1)

        store.markUploaded(queued)
        XCTAssertTrue(store.profile.pendingUploads.isEmpty)
    }

    func testRecentRunsAreCappedAndNewestFirst() {
        for score in 1...60 {
            _ = store.record(run: TestSupport.run(score: score), mode: .classic, deathCause: .pipe)
        }

        XCTAssertEqual(store.profile.recentRuns.count, 50, "Older runs are pruned")
        XCTAssertEqual(store.profile.recentRuns.first?.score, 60)
    }

    // MARK: - Wallet & skins

    func testClassicSkinIsAlwaysAvailable() {
        XCTAssertTrue(store.isUnlocked(.classic))
        XCTAssertFalse(store.isUnlocked(.phoenix))
    }

    func testPurchaseRequiresEnoughCoins() {
        XCTAssertFalse(store.purchase(.mint), "Cannot buy with an empty wallet")

        store.update { $0.wallet = BirdSkin.mint.price }
        XCTAssertTrue(store.purchase(.mint))
        XCTAssertTrue(store.isUnlocked(.mint))
        XCTAssertEqual(store.profile.wallet, 0, "Coins are spent")
    }

    func testPurchasingTwiceDoesNotDoubleCharge() {
        store.update { $0.wallet = BirdSkin.mint.price * 2 }
        XCTAssertTrue(store.purchase(.mint))
        XCTAssertFalse(store.purchase(.mint), "Already owned")
        XCTAssertEqual(store.profile.wallet, BirdSkin.mint.price)
    }

    // MARK: - Achievements

    func testAchievementProgressIsMonotonic() {
        store.setProgress(10, unlocked: false, for: "combo_artist")
        store.setProgress(4, unlocked: false, for: "combo_artist")
        XCTAssertEqual(store.progress(for: "combo_artist").progress, 10, "Progress never regresses")

        store.setProgress(12, unlocked: true, for: "combo_artist")
        XCTAssertTrue(store.progress(for: "combo_artist").isUnlocked)

        let unlockedAt = store.progress(for: "combo_artist").unlockedAt
        store.setProgress(20, unlocked: true, for: "combo_artist")
        XCTAssertEqual(store.progress(for: "combo_artist").unlockedAt, unlockedAt, "Unlock time is stable")
    }

    // MARK: - Daily challenge

    func testDailyCompletionsAreDeduplicated() {
        store.markDailyCompleted("2026-03-19")
        store.markDailyCompleted("2026-03-19")
        store.markDailyCompleted("2026-03-20")

        XCTAssertEqual(store.dailyChallengeStreakCount, 2)
    }

    // MARK: - Ghost

    func testGhostIsOnlyReplacedByABetterRun() {
        store.storeGhost(samples: [0.1, 0.2], score: 10)
        XCTAssertEqual(store.ghost?.score, 10)

        store.storeGhost(samples: [0.9], score: 5)
        XCTAssertEqual(store.ghost?.samples.count, 2, "A worse run must not overwrite the ghost")

        store.storeGhost(samples: [0.3, 0.4, 0.5], score: 22)
        XCTAssertEqual(store.ghost?.score, 22)
        XCTAssertEqual(store.ghost?.samples.count, 3)
    }

    func testGhostSamplesAreCapped() {
        store.storeGhost(samples: Array(repeating: 0.5, count: GameConfig.ghostMaxSamples + 100), score: 1)
        XCTAssertEqual(store.ghost?.samples.count, GameConfig.ghostMaxSamples)
    }

    // MARK: - Persistence & reset

    func testProfileSurvivesANewStoreOverTheSameDefaults() {
        let defaults = TestSupport.isolatedDefaults("persistence")
        let first = GameStore(defaults: defaults)
        _ = first.record(run: TestSupport.run(score: 33, coins: 5), mode: .endless, deathCause: .pipe)

        let second = GameStore(defaults: defaults)
        XCTAssertEqual(second.profile.bestScore(for: .endless), 33)
        XCTAssertEqual(second.profile.wallet, 5)
    }

    func testResetProgressClearsEverything() {
        _ = store.record(run: TestSupport.run(score: 50, coins: 20), mode: .classic, deathCause: .pipe)
        store.setProgress(1, unlocked: true, for: "first_flight")

        store.resetProgress()

        XCTAssertEqual(store.profile.overallBest, 0)
        XCTAssertEqual(store.profile.wallet, 0)
        XCTAssertTrue(store.profile.achievements.isEmpty)
        XCTAssertTrue(store.profile.recentRuns.isEmpty)
        XCTAssertTrue(store.isUnlocked(.classic), "The default skin stays available")
    }

    // MARK: - Settings

    func testSettingsDefaults() {
        let settings = TestSupport.makeSettings()

        XCTAssertTrue(settings.soundEnabled)
        XCTAssertTrue(settings.hapticsEnabled)
        XCTAssertTrue(settings.ghostEnabled)
        XCTAssertTrue(settings.onlineEnabled)
        XCTAssertFalse(settings.showFPS)
        XCTAssertFalse(settings.highContrast)
        XCTAssertFalse(settings.reduceFlashing)
        XCTAssertEqual(settings.selectedSkin, .classic)
        XCTAssertEqual(settings.selectedMode, .classic)
        XCTAssertNil(settings.backendURLOverride)
    }

    func testSettingsRoundTrip() {
        let defaults = TestSupport.isolatedDefaults("settings")
        let settings = Settings(defaults: defaults)

        settings.soundEnabled = false
        settings.selectedSkin = .phoenix
        settings.selectedMode = .hardcore
        settings.backendURLOverride = "http://192.168.1.5:4000"

        let reloaded = Settings(defaults: defaults)
        XCTAssertFalse(reloaded.soundEnabled)
        XCTAssertEqual(reloaded.selectedSkin, .phoenix)
        XCTAssertEqual(reloaded.selectedMode, .hardcore)
        XCTAssertEqual(reloaded.backendURLOverride, "http://192.168.1.5:4000")
    }

    func testBlankBackendURLIsTreatedAsUnset() {
        let settings = TestSupport.makeSettings()
        settings.backendURLOverride = "   "
        XCTAssertNil(settings.backendURLOverride)
    }

    func testDeviceIdIsStableAcrossReads() {
        let settings = TestSupport.makeSettings()
        let first = settings.deviceId
        XCTAssertFalse(first.isEmpty)
        XCTAssertEqual(first, settings.deviceId, "Guest accounts depend on a stable id")
    }
}
