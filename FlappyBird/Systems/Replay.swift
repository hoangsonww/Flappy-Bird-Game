import CoreGraphics
import Foundation

/// A recorded run, replayable frame for frame.
///
/// ## Why this shape
///
/// A replay could in principle be rebuilt from the run's seed, since the world
/// is generated from it — but pipe spawning is driven by accumulated frame time,
/// so two plays of the same seed do not line up exactly. Recording what actually
/// happened removes the question.
///
/// It stays small because a pipe's motion is fully determined the moment it
/// spawns: the scene gives each pair one `moveBy` over a fixed duration and
/// never touches it again. So an obstacle needs its spawn time and geometry,
/// not a position per frame.
///
/// Everything is stored as a fraction of the scene, so a run recorded on one
/// device plays back correctly on another.
struct Replay: Codable, Equatable, Identifiable {

    /// One sampled moment of the bird's flight.
    struct Frame: Codable, Equatable {
        /// Seconds since the run started.
        var time: TimeInterval
        /// Height as a fraction of the scene height.
        var height: Double
        /// Bird rotation in radians.
        var rotation: Double
    }

    /// A pipe pair as it entered the world.
    struct Obstacle: Codable, Equatable {
        /// Seconds since the run started.
        var time: TimeInterval
        /// Centre of the opening, as a fraction of the scene height.
        var gapCentre: Double
        /// Height of the opening, as a fraction of the scene height.
        var gapHeight: Double
        /// Where the pair entered, as a fraction of the scene width.
        var startX: Double
        /// How far it travelled, as a fraction of the scene width.
        var travel: Double
        /// How long that took.
        var duration: TimeInterval
    }

    var id: UUID
    var mode: GameMode
    var score: Int
    var coins: Int
    var pipesPassed: Int
    var recordedAt: Date
    var frames: [Frame]
    var obstacles: [Obstacle]

    init(
        id: UUID = UUID(),
        mode: GameMode,
        score: Int,
        coins: Int,
        pipesPassed: Int,
        recordedAt: Date = Date(),
        frames: [Frame],
        obstacles: [Obstacle]
    ) {
        self.id = id
        self.mode = mode
        self.score = score
        self.coins = coins
        self.pipesPassed = pipesPassed
        self.recordedAt = recordedAt
        self.frames = frames
        self.obstacles = obstacles
    }

    /// Length of the recording.
    var duration: TimeInterval { frames.last?.time ?? 0 }

    /// A single frame cannot be interpolated, so it is not worth showing.
    var isPlayable: Bool { frames.count >= 2 }
}

/// Captures a run as it is played.
///
/// The scene owns one of these and drives it from `update(_:)`. It is a class
/// because the scene mutates it every frame from several call sites.
final class ReplayRecorder {

    private(set) var frames: [Replay.Frame] = []
    private(set) var obstacles: [Replay.Obstacle] = []

    /// Seconds of recorded run so far. Obstacles are stamped with this.
    private(set) var elapsed: TimeInterval = 0

    private var sinceLastFrame: TimeInterval = 0

    /// Advance the clock. Call once per frame, before anything is recorded.
    func advance(by deltaTime: TimeInterval) {
        guard deltaTime > 0 else { return }
        elapsed += deltaTime
        sinceLastFrame += deltaTime
    }

    /// Sample the bird, if the sampling interval has passed.
    func record(height: Double, rotation: Double) {
        guard frames.count < GameConfig.replayMaxFrames else { return }
        // The first sample is taken immediately so a replay always opens on the
        // bird's real starting pose rather than interpolating up from nothing.
        guard frames.isEmpty || sinceLastFrame >= GameConfig.replaySampleInterval else { return }
        sinceLastFrame = 0
        frames.append(
            Replay.Frame(
                time: elapsed,
                height: min(1, max(0, height)),
                rotation: rotation
            )
        )
    }

    /// Note a pipe pair entering the world.
    func recordObstacle(gapCentre: Double, gapHeight: Double, startX: Double, travel: Double, duration: TimeInterval) {
        guard obstacles.count < GameConfig.replayMaxObstacles else { return }
        obstacles.append(
            Replay.Obstacle(
                time: elapsed,
                gapCentre: gapCentre,
                gapHeight: gapHeight,
                startX: startX,
                travel: travel,
                duration: duration
            )
        )
    }

    func reset() {
        frames.removeAll(keepingCapacity: true)
        obstacles.removeAll(keepingCapacity: true)
        elapsed = 0
        sinceLastFrame = 0
    }

    /// Seal the recording, or `nil` when there is not enough of it to watch.
    func finish(mode: GameMode, score: Int, coins: Int, pipesPassed: Int, recordedAt: Date = Date()) -> Replay? {
        let replay = Replay(
            mode: mode,
            score: score,
            coins: coins,
            pipesPassed: pipesPassed,
            recordedAt: recordedAt,
            frames: frames,
            obstacles: obstacles
        )
        guard replay.isPlayable, replay.duration >= GameConfig.replayMinimumDuration else { return nil }
        return replay
    }
}

/// Reads a `Replay` back at an arbitrary point in time.
///
/// Deliberately a value type with no scene knowledge: the playback scene owns
/// the nodes, this owns only the clock and the interpolation, which is what
/// makes both of them testable on their own.
struct ReplayPlayer {

    /// An obstacle and where it sits at the current playback time.
    struct VisibleObstacle {
        let index: Int
        let obstacle: Replay.Obstacle
        /// Position as a fraction of the scene width.
        let x: Double
    }

    let replay: Replay
    private(set) var time: TimeInterval = 0

    mutating func advance(by deltaTime: TimeInterval) {
        seek(to: time + deltaTime)
    }

    /// Jump to `target`, clamped to the recording.
    mutating func seek(to target: TimeInterval) {
        time = min(replay.duration, max(0, target))
    }

    mutating func restart() {
        time = 0
    }

    var hasFinished: Bool { time >= replay.duration }

    /// 0…1 through the recording, for a progress bar.
    var progress: Double {
        guard replay.duration > 0 else { return 0 }
        return min(1, max(0, time / replay.duration))
    }

    /// The bird's pose at the current time, interpolated between samples.
    var pose: (height: Double, rotation: Double)? {
        let frames = replay.frames
        guard let first = frames.first, let last = frames.last else { return nil }
        if time <= first.time { return (first.height, first.rotation) }
        if time >= last.time { return (last.height, last.rotation) }

        // Frames are in time order, so a binary search beats walking the list
        // every frame on a long recording.
        var low = 0
        var high = frames.count - 1
        while high - low > 1 {
            let middle = (low + high) / 2
            if frames[middle].time <= time { low = middle } else { high = middle }
        }

        let start = frames[low]
        let end = frames[high]
        let span = end.time - start.time
        guard span > 0 else { return (start.height, start.rotation) }

        let fraction = (time - start.time) / span
        return (
            start.height + (end.height - start.height) * fraction,
            start.rotation + (end.rotation - start.rotation) * fraction
        )
    }

    /// Obstacles that should be on screen at the current time.
    ///
    /// A pair is visible from its spawn until it finishes travelling; its x is
    /// a straight interpolation because that is exactly what the live scene's
    /// single `moveBy` action does.
    func visibleObstacles() -> [VisibleObstacle] {
        replay.obstacles.enumerated().compactMap { index, obstacle in
            let age = time - obstacle.time
            guard age >= 0, age <= obstacle.duration else { return nil }
            guard obstacle.duration > 0 else {
                return VisibleObstacle(index: index, obstacle: obstacle, x: obstacle.startX)
            }
            let fraction = age / obstacle.duration
            return VisibleObstacle(
                index: index,
                obstacle: obstacle,
                x: obstacle.startX - obstacle.travel * fraction
            )
        }
    }
}
