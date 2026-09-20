import XCTest
@testable import FlappyBird

/// The recorder, the player and the store that keeps recordings.
final class ReplayTests: XCTestCase {

    // MARK: - Recording

    /// Feed the recorder a run at a fixed frame rate.
    private func record(
        seconds: TimeInterval,
        frameRate: TimeInterval = 1.0 / 60.0,
        height: (Int) -> Double = { _ in 0.5 }
    ) -> ReplayRecorder {
        let recorder = ReplayRecorder()
        let frames = Int(seconds / frameRate)
        for frame in 0..<frames {
            recorder.advance(by: frameRate)
            recorder.record(height: height(frame), rotation: 0)
        }
        return recorder
    }

    func testRecordingSamplesAtTheConfiguredRate() {
        let recorder = record(seconds: 2)

        // 2 seconds at 30 Hz, plus the immediate first sample.
        let expected = Int(2.0 / GameConfig.replaySampleInterval)
        XCTAssertEqual(Double(recorder.frames.count), Double(expected), accuracy: 2)
    }

    func testTheFirstSampleIsTakenImmediately() {
        let recorder = ReplayRecorder()
        recorder.advance(by: 1.0 / 60.0)
        recorder.record(height: 0.75, rotation: 0.1)

        XCTAssertEqual(recorder.frames.count, 1, "A replay must open on the real starting pose")
        XCTAssertEqual(recorder.frames.first?.height, 0.75)
    }

    func testHeightsAreClampedToTheScene() {
        let recorder = ReplayRecorder()
        recorder.advance(by: 1)
        recorder.record(height: 4.2, rotation: 0)
        recorder.advance(by: 1)
        recorder.record(height: -3, rotation: 0)

        XCTAssertEqual(recorder.frames.map(\.height), [1, 0])
    }

    func testFramesAreCapped() {
        let recorder = record(seconds: 600)
        XCTAssertEqual(recorder.frames.count, GameConfig.replayMaxFrames)
    }

    func testObstaclesAreStampedWithTheCurrentTime() {
        let recorder = ReplayRecorder()
        recorder.advance(by: 1.5)
        recorder.recordObstacle(gapCentre: 0.5, gapHeight: 0.2, startX: 1.1, travel: 1.4, duration: 3)

        XCTAssertEqual(recorder.obstacles.count, 1)
        XCTAssertEqual(recorder.obstacles.first?.time ?? 0, 1.5, accuracy: 0.0001)
    }

    func testObstaclesAreCapped() {
        let recorder = ReplayRecorder()
        for _ in 0..<(GameConfig.replayMaxObstacles + 50) {
            recorder.recordObstacle(gapCentre: 0.5, gapHeight: 0.2, startX: 1, travel: 1, duration: 1)
        }
        XCTAssertEqual(recorder.obstacles.count, GameConfig.replayMaxObstacles)
    }

    func testResetClearsEverything() {
        let recorder = record(seconds: 3)
        recorder.recordObstacle(gapCentre: 0.5, gapHeight: 0.2, startX: 1, travel: 1, duration: 1)
        recorder.reset()

        XCTAssertTrue(recorder.frames.isEmpty)
        XCTAssertTrue(recorder.obstacles.isEmpty)
        XCTAssertEqual(recorder.elapsed, 0)
    }

    func testAVeryShortRunIsNotWorthKeeping() {
        let recorder = record(seconds: 0.4)
        XCTAssertNil(
            recorder.finish(mode: .classic, score: 0, coins: 0, pipesPassed: 0),
            "A run under the minimum duration should produce no replay"
        )
    }

    func testFinishCarriesTheRunsSummary() throws {
        let recorder = record(seconds: 5)
        let replay = try XCTUnwrap(recorder.finish(mode: .hardcore, score: 12, coins: 7, pipesPassed: 12))

        XCTAssertEqual(replay.mode, .hardcore)
        XCTAssertEqual(replay.score, 12)
        XCTAssertEqual(replay.coins, 7)
        XCTAssertEqual(replay.pipesPassed, 12)
        XCTAssertEqual(replay.duration, 5, accuracy: 0.1)
        XCTAssertTrue(replay.isPlayable)
    }

    // MARK: - Playback

    private func makeReplay(
        frames: [Replay.Frame],
        obstacles: [Replay.Obstacle] = []
    ) -> Replay {
        Replay(mode: .classic, score: 1, coins: 0, pipesPassed: 1, frames: frames, obstacles: obstacles)
    }

    func testPoseInterpolatesBetweenSamples() {
        let replay = makeReplay(frames: [
            Replay.Frame(time: 0, height: 0, rotation: 0),
            Replay.Frame(time: 1, height: 1, rotation: 2),
        ])
        var player = ReplayPlayer(replay: replay)

        player.seek(to: 0.25)
        XCTAssertEqual(player.pose?.height ?? 0, 0.25, accuracy: 0.0001)
        XCTAssertEqual(player.pose?.rotation ?? 0, 0.5, accuracy: 0.0001)
    }

    func testPoseHoldsTheEndsRatherThanExtrapolating() {
        let replay = makeReplay(frames: [
            Replay.Frame(time: 1, height: 0.2, rotation: 0),
            Replay.Frame(time: 2, height: 0.8, rotation: 1),
        ])
        var player = ReplayPlayer(replay: replay)

        player.seek(to: -5)
        XCTAssertEqual(player.pose?.height, 0.2)

        player.seek(to: 99)
        XCTAssertEqual(player.pose?.height, 0.8)
    }

    /// The binary search has to land on the right pair at every point.
    func testPoseIsCorrectAcrossManySamples() {
        let frames = (0..<200).map {
            Replay.Frame(time: Double($0) * 0.1, height: Double($0) / 200, rotation: 0)
        }
        var player = ReplayPlayer(replay: makeReplay(frames: frames))

        for step in stride(from: 0.0, through: 19.9, by: 0.37) {
            player.seek(to: step)
            let expected = step / 20
            XCTAssertEqual(player.pose?.height ?? 0, expected, accuracy: 0.01, "at t=\(step)")
        }
    }

    func testSeekIsClampedAndProgressTracksIt() {
        let replay = makeReplay(frames: [
            Replay.Frame(time: 0, height: 0, rotation: 0),
            Replay.Frame(time: 4, height: 1, rotation: 0),
        ])
        var player = ReplayPlayer(replay: replay)

        player.seek(to: -10)
        XCTAssertEqual(player.time, 0)
        XCTAssertEqual(player.progress, 0)

        player.seek(to: 2)
        XCTAssertEqual(player.progress, 0.5, accuracy: 0.0001)

        player.seek(to: 100)
        XCTAssertEqual(player.time, 4)
        XCTAssertEqual(player.progress, 1)
        XCTAssertTrue(player.hasFinished)

        player.restart()
        XCTAssertEqual(player.time, 0)
        XCTAssertFalse(player.hasFinished)
    }

    func testObstaclesAreVisibleOnlyWhileTravelling() {
        let obstacle = Replay.Obstacle(
            time: 1,
            gapCentre: 0.5,
            gapHeight: 0.2,
            startX: 1.2,
            travel: 1.6,
            duration: 4
        )
        let replay = makeReplay(
            frames: [
                Replay.Frame(time: 0, height: 0.5, rotation: 0),
                Replay.Frame(time: 10, height: 0.5, rotation: 0),
            ],
            obstacles: [obstacle]
        )
        var player = ReplayPlayer(replay: replay)

        player.seek(to: 0.5)
        XCTAssertTrue(player.visibleObstacles().isEmpty, "Not spawned yet")

        player.seek(to: 1)
        XCTAssertEqual(player.visibleObstacles().first?.x ?? 0, 1.2, accuracy: 0.0001, "At its entry point")

        player.seek(to: 3)
        XCTAssertEqual(player.visibleObstacles().first?.x ?? 0, 1.2 - 1.6 * 0.5, accuracy: 0.0001)

        player.seek(to: 9)
        XCTAssertTrue(player.visibleObstacles().isEmpty, "Finished travelling")
    }

    func testVisibleObstaclesCarryTheirIndex() {
        let obstacles = (0..<3).map {
            Replay.Obstacle(
                time: Double($0),
                gapCentre: 0.5,
                gapHeight: 0.2,
                startX: 1,
                travel: 1,
                duration: 10
            )
        }
        let replay = makeReplay(
            frames: [
                Replay.Frame(time: 0, height: 0.5, rotation: 0),
                Replay.Frame(time: 10, height: 0.5, rotation: 0),
            ],
            obstacles: obstacles
        )
        var player = ReplayPlayer(replay: replay)
        player.seek(to: 5)

        XCTAssertEqual(player.visibleObstacles().map(\.index), [0, 1, 2])
    }

    // MARK: - Storage

    private func makeStore(_ name: String = #function) -> ReplayStore {
        let defaults = TestSupport.isolatedDefaults("replays-\(name)")
        return ReplayStore(defaults: defaults, storageKey: "replays.test")
    }

    private func sample(score: Int, id: UUID = UUID()) -> Replay {
        Replay(
            id: id,
            mode: .classic,
            score: score,
            coins: 0,
            pipesPassed: score,
            frames: [
                Replay.Frame(time: 0, height: 0.5, rotation: 0),
                Replay.Frame(time: 2, height: 0.6, rotation: 0),
            ],
            obstacles: []
        )
    }

    func testSavedReplaysComeBackNewestFirst() {
        let store = makeStore()
        store.save(sample(score: 1))
        store.save(sample(score: 2))
        store.save(sample(score: 3))

        XCTAssertEqual(store.replays.map(\.score), [3, 2, 1])
    }

    func testTheOldestReplayIsDroppedAtTheLimit() {
        let store = makeStore()
        for score in 1...(ReplayStore.limit + 5) {
            store.save(sample(score: score))
        }

        XCTAssertEqual(store.replays.count, ReplayStore.limit)
        XCTAssertEqual(store.replays.first?.score, ReplayStore.limit + 5)
        XCTAssertEqual(store.replays.last?.score, 6, "The five oldest should have gone")
    }

    func testSavingTheSameReplayTwiceDoesNotDuplicateIt() {
        let store = makeStore()
        let id = UUID()
        store.save(sample(score: 5, id: id))
        store.save(sample(score: 9, id: id))

        XCTAssertEqual(store.replays.count, 1)
        XCTAssertEqual(store.replays.first?.score, 9)
    }

    func testAnUnplayableReplayIsRejected() {
        let store = makeStore()
        store.save(
            Replay(
                mode: .classic,
                score: 0,
                coins: 0,
                pipesPassed: 0,
                frames: [Replay.Frame(time: 0, height: 0.5, rotation: 0)],
                obstacles: []
            )
        )
        XCTAssertTrue(store.replays.isEmpty, "One frame cannot be interpolated")
    }

    func testDeleteAndRemoveAll() {
        let store = makeStore()
        let id = UUID()
        store.save(sample(score: 1, id: id))
        store.save(sample(score: 2))

        store.delete(id: id)
        XCTAssertEqual(store.replays.map(\.score), [2])

        store.removeAll()
        XCTAssertTrue(store.replays.isEmpty)
    }

    func testReplaysSurviveAReload() throws {
        let defaults = TestSupport.isolatedDefaults("replays-reload")
        let first = ReplayStore(defaults: defaults, storageKey: "replays.test")
        first.save(sample(score: 41))

        let second = ReplayStore(defaults: defaults, storageKey: "replays.test")
        XCTAssertEqual(second.replays.count, 1)
        let stored = try XCTUnwrap(second.replays.first)
        XCTAssertEqual(stored.score, 41)
        XCTAssertEqual(stored.frames.count, 2)
    }

    func testLookupById() {
        let store = makeStore()
        let id = UUID()
        store.save(sample(score: 7, id: id))

        XCTAssertEqual(store.replay(with: id)?.score, 7)
        XCTAssertNil(store.replay(with: UUID()))
    }

    // MARK: - Playback geometry

    /// Playback must place the bird exactly where the game did.
    ///
    /// The replay scene used its own `0.28` while the game used `0.32`, so a
    /// recording showed the bird 4% of the screen from where it actually flew —
    /// pipes arrived at the wrong moment and it appeared to clip obstacles it
    /// had cleared. Both now read this constant.
    func testTheBirdIsPlacedWhereTheGamePutIt() {
        XCTAssertEqual(GameConfig.birdStartX, 0.32, accuracy: 0.0001)
        XCTAssertEqual(GameConfig.birdStartY, 0.62, accuracy: 0.0001)
    }

    /// Seeded demo data must never contain fabricated recordings.
    func testSeedingLeavesNoFabricatedReplays() {
        let defaults = TestSupport.isolatedDefaults("replays-seed")
        let store = ReplayStore(defaults: defaults, storageKey: "replays.test")
        store.save(sample(score: 3))
        XCTAssertFalse(store.replays.isEmpty)

        // Seeding resets the store; nothing synthetic is written back.
        store.removeAll()
        XCTAssertTrue(
            store.replays.isEmpty,
            "A replay list should only ever contain runs that were actually played"
        )
    }
}
