import CoreGraphics
import Foundation

/// Records and replays the bird's flight path.
///
/// A run is sampled at a fixed rate (`GameConfig.ghostSampleInterval`) and stored
/// as normalised heights (`0…1` of scene height) so a replay looks right on any
/// device, regardless of the screen it was recorded on.
final class GhostRecorder {
    private(set) var samples: [Double] = []
    private var accumulator: TimeInterval = 0

    /// Record a sample if enough time has passed.
    func record(normalisedHeight: Double, deltaTime: TimeInterval) {
        accumulator += deltaTime
        guard accumulator >= GameConfig.ghostSampleInterval else { return }
        accumulator -= GameConfig.ghostSampleInterval
        guard samples.count < GameConfig.ghostMaxSamples else { return }
        samples.append(min(1, max(0, normalisedHeight)))
    }

    func reset() {
        samples.removeAll(keepingCapacity: true)
        accumulator = 0
    }
}

/// Plays back a recorded path.
struct GhostPlayer {
    let samples: [Double]
    let score: Int
    private var elapsed: TimeInterval = 0

    init(samples: [Double], score: Int) {
        self.samples = samples
        self.score = score
    }

    var isEmpty: Bool { samples.isEmpty }

    /// Total length of the recording.
    var duration: TimeInterval { Double(samples.count) * GameConfig.ghostSampleInterval }

    mutating func advance(by deltaTime: TimeInterval) {
        elapsed += deltaTime
    }

    mutating func reset() {
        elapsed = 0
    }

    var hasFinished: Bool { elapsed >= duration }

    /// Interpolated normalised height at the current playback position,
    /// or `nil` once the recording has run out.
    var currentHeight: Double? {
        guard !samples.isEmpty else { return nil }
        let position = elapsed / GameConfig.ghostSampleInterval
        let index = Int(position)
        guard index < samples.count - 1 else { return nil }

        let fraction = position - Double(index)
        let current = samples[index]
        let next = samples[index + 1]
        return current + (next - current) * fraction
    }
}
