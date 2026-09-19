import XCTest

@testable import FlappyBird

/// Ghost sampling and interpolated playback.
final class GhostRecorderTests: XCTestCase {

    func testRecorderSamplesAtTheConfiguredRate() {
        let recorder = GhostRecorder()
        let step = GameConfig.ghostSampleInterval

        // Ten intervals worth of frames, delivered in half-interval slices.
        for _ in 0..<20 {
            recorder.record(normalisedHeight: 0.5, deltaTime: step / 2)
        }

        XCTAssertEqual(recorder.samples.count, 10, "Two half-steps should yield one sample")
    }

    func testRecorderClampsHeights() {
        let recorder = GhostRecorder()
        recorder.record(normalisedHeight: 3.2, deltaTime: GameConfig.ghostSampleInterval)
        recorder.record(normalisedHeight: -1.4, deltaTime: GameConfig.ghostSampleInterval)

        XCTAssertEqual(recorder.samples, [1.0, 0.0])
    }

    func testRecorderRespectsTheSampleCap() {
        let recorder = GhostRecorder()
        for _ in 0..<(GameConfig.ghostMaxSamples + 50) {
            recorder.record(normalisedHeight: 0.4, deltaTime: GameConfig.ghostSampleInterval)
        }
        XCTAssertEqual(recorder.samples.count, GameConfig.ghostMaxSamples)
    }

    func testResetEmptiesTheBuffer() {
        let recorder = GhostRecorder()
        recorder.record(normalisedHeight: 0.5, deltaTime: GameConfig.ghostSampleInterval)
        recorder.reset()
        XCTAssertTrue(recorder.samples.isEmpty)
    }

    func testPlayerInterpolatesBetweenSamples() {
        var player = GhostPlayer(samples: [0.0, 1.0, 1.0], score: 10)
        XCTAssertEqual(player.currentHeight ?? -1, 0.0, accuracy: 0.0001)

        player.advance(by: GameConfig.ghostSampleInterval / 2)
        XCTAssertEqual(player.currentHeight ?? -1, 0.5, accuracy: 0.0001, "Halfway between 0 and 1")

        player.advance(by: GameConfig.ghostSampleInterval / 2)
        XCTAssertEqual(player.currentHeight ?? -1, 1.0, accuracy: 0.0001)
    }

    func testPlayerReportsNilPastTheEnd() {
        var player = GhostPlayer(samples: [0.2, 0.4], score: 3)
        player.advance(by: GameConfig.ghostSampleInterval * 5)

        XCTAssertNil(player.currentHeight)
        XCTAssertTrue(player.hasFinished)
    }

    func testEmptyPlayerIsInert() {
        var player = GhostPlayer(samples: [], score: 0)
        XCTAssertTrue(player.isEmpty)
        XCTAssertNil(player.currentHeight)
        player.advance(by: 5)
        XCTAssertNil(player.currentHeight)
    }

    func testDurationMatchesSampleCount() {
        let player = GhostPlayer(samples: Array(repeating: 0.5, count: 40), score: 1)
        XCTAssertEqual(player.duration, 40 * GameConfig.ghostSampleInterval, accuracy: 0.0001)
    }

    func testResetRewindsPlayback() {
        var player = GhostPlayer(samples: [0.1, 0.9, 0.5], score: 2)
        player.advance(by: GameConfig.ghostSampleInterval * 2)
        player.reset()
        XCTAssertEqual(player.currentHeight ?? -1, 0.1, accuracy: 0.0001)
    }
}
