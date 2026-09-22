import CoreGraphics
import Foundation

/// Resolved difficulty for one point in a run.
struct DifficultySnapshot: Equatable {
    /// Vertical gap between the two pipes, in points.
    var pipeGap: CGFloat
    /// Seconds between spawns.
    var spawnInterval: TimeInterval
    /// Seconds per point of horizontal travel (lower is faster).
    var scrollRate: TimeInterval
    /// Gravity applied to the bird.
    var gravity: CGFloat

    /// Distance between one pipe pair and the next, in points.
    ///
    /// `scrollRate` is seconds per point, so this is what the spawn interval
    /// actually buys the player on screen. Useful for reasoning about spacing:
    /// the *time* window is `spawnInterval`, but two modes with the same window
    /// look very different if one scrolls faster.
    var horizontalSpacing: CGFloat {
        guard scrollRate > 0 else { return 0 }
        return CGFloat(spawnInterval / scrollRate)
    }
}

/// Maps "how far into the run are we?" onto concrete difficulty numbers.
///
/// The curve is intentionally smooth and bounded: it eases in over the first 40
/// pipes and then holds, so a great run stays hard but never becomes impossible.
struct DifficultyCurve {
    let mode: GameMode
    /// Extra scaling from a daily challenge (1.0 when not playing one).
    var pipeGapOverride: CGFloat?
    var gravityScale: CGFloat = 1
    var speedScale: CGFloat = 1

    /// Pipes cleared before the curve reaches its hardest values.
    private let rampLength: CGFloat = 40

    init(
        mode: GameMode,
        pipeGapOverride: CGFloat? = nil,
        gravityScale: CGFloat = 1,
        speedScale: CGFloat = 1
    ) {
        self.mode = mode
        self.pipeGapOverride = pipeGapOverride
        self.gravityScale = gravityScale
        self.speedScale = speedScale
    }

    /// `0` at the start of a run, easing to `1` once `rampLength` pipes are cleared.
    func progress(pipesPassed: Int) -> CGFloat {
        guard mode.ramps else { return 0 }
        let linear = min(1, CGFloat(max(0, pipesPassed)) / rampLength)
        // Ease-out cubic: most of the difficulty arrives early, then plateaus.
        return 1 - pow(1 - linear, 3)
    }

    func snapshot(pipesPassed: Int) -> DifficultySnapshot {
        let t = progress(pipesPassed: pipesPassed)

        let startGap = pipeGapOverride ?? mode.startingPipeGap
        let endGap = max(GameConfig.minimumVerticalPipeGap, startGap - 44)
        let gap = startGap + (endGap - startGap) * t

        let startInterval = GameConfig.baseSpawnInterval
        let endInterval = GameConfig.minimumSpawnInterval
        let interval = startInterval + (endInterval - startInterval) * TimeInterval(t)

        let startRate = GameConfig.baseScrollRate * TimeInterval(mode.scrollMultiplier / speedScale)
        let endRate = GameConfig.fastestScrollRate * TimeInterval(mode.scrollMultiplier / speedScale)
        let rate = startRate + (endRate - startRate) * TimeInterval(t)

        return DifficultySnapshot(
            pipeGap: gap,
            spawnInterval: max(GameConfig.minimumSpawnInterval, interval),
            scrollRate: max(GameConfig.fastestScrollRate * 0.8, rate),
            gravity: GameConfig.gravity * mode.gravityMultiplier * gravityScale
        )
    }

    /// Human-readable tier used by the HUD ("Level 3").
    func level(pipesPassed: Int) -> Int {
        1 + Int(progress(pipesPassed: pipesPassed) * 5)
    }
}
