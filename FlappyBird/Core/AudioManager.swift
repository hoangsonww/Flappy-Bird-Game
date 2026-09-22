import AVFoundation
import Foundation

/// Procedurally synthesised sound effects.
///
/// The repository ships no audio assets, so every effect is generated at launch
/// as a short PCM buffer and played through `AVAudioEngine`. That keeps the clone
/// step light, avoids licensing questions, and still gives the game a chiptune
/// voice. If a real asset is ever dropped into the bundle it can simply replace
/// the matching case in `Effect`.
final class AudioManager {
    static let shared = AudioManager()

    /// One entry per sound the game can make.
    enum Effect: CaseIterable {
        case flap, score, coin, powerUp, crash, achievement, uiTap, countdown
        case combo, bounce, pause, resume, personalBest

        /// Ascending/descending tone steps in Hz.
        fileprivate var tones: [Float] {
            switch self {
            case .flap: return [520, 700]
            case .score: return [880, 1_180]
            case .coin: return [1_046, 1_318, 1_568]
            case .powerUp: return [660, 880, 1_100, 1_320]
            case .crash: return [220, 160, 110]
            case .achievement: return [880, 1_108, 1_318, 1_760]
            case .uiTap: return [740]
            case .countdown: return [620]
            case .combo: return [988, 1_318]
            case .bounce: return [300, 430]
            case .pause: return [620, 440]
            case .resume: return [440, 620]
            case .personalBest: return [880, 1_108, 1_318, 1_568, 1_976]
            }
        }

        /// Total duration in seconds.
        fileprivate var duration: Float {
            switch self {
            case .flap: return 0.07
            case .score: return 0.10
            case .coin: return 0.16
            case .powerUp: return 0.26
            case .crash: return 0.34
            case .achievement: return 0.42
            case .uiTap: return 0.05
            case .countdown: return 0.09
            case .combo: return 0.12
            case .bounce: return 0.11
            case .pause, .resume: return 0.14
            case .personalBest: return 0.60
            }
        }

        fileprivate var amplitude: Float {
            switch self {
            case .crash: return 0.35
            case .flap, .uiTap: return 0.18
            case .bounce, .pause, .resume: return 0.20
            case .personalBest: return 0.26
            default: return 0.24
            }
        }

        /// Square waves read as 8-bit; triangle waves are gentler for UI.
        fileprivate var isSquare: Bool {
            switch self {
            case .uiTap, .countdown, .bounce, .pause, .resume: return false
            default: return true
            }
        }
    }

    private let engine = AVAudioEngine()
    private var players: [Effect: AVAudioPlayerNode] = [:]
    private var buffers: [Effect: AVAudioPCMBuffer] = [:]
    private let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)
    private var isConfigured = false

    private init() {}

    // MARK: - Lifecycle

    /// Build the graph. Safe to call more than once.
    func start() {
        guard !isConfigured, let format else { return }
        isConfigured = true

        configureSession()

        for effect in Effect.allCases {
            let player = AVAudioPlayerNode()
            engine.attach(player)
            engine.connect(player, to: engine.mainMixerNode, format: format)
            players[effect] = player
            buffers[effect] = makeBuffer(for: effect, format: format)
        }

        do {
            try engine.start()
            players.values.forEach { $0.play() }
        } catch {
            // Audio is a nice-to-have; a failure here must never break gameplay.
            isConfigured = false
        }
    }

    func stop() {
        guard isConfigured else { return }
        players.values.forEach { $0.stop() }
        engine.stop()
        isConfigured = false
    }

    /// Call when the app returns to the foreground — iOS may have torn the engine down.
    func resumeIfNeeded() {
        guard isConfigured, !engine.isRunning else { return }
        try? engine.start()
        players.values.forEach { if !$0.isPlaying { $0.play() } }
    }

    // MARK: - Playback

    func play(_ effect: Effect) {
        guard Settings.shared.soundEnabled else { return }
        if !isConfigured { start() }
        guard let player = players[effect], let buffer = buffers[effect], engine.isRunning else { return }
        player.scheduleBuffer(buffer, at: nil, options: .interrupts, completionHandler: nil)
    }

    // MARK: - Synthesis

    private func configureSession() {
        let session = AVAudioSession.sharedInstance()
        // `.ambient` keeps the player's own music going — respectful default for a casual game.
        try? session.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
        try? session.setActive(true)
    }

    /// Render an effect into a mono PCM buffer.
    private func makeBuffer(for effect: Effect, format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let sampleRate = Float(format.sampleRate)
        let frameCount = AVAudioFrameCount(effect.duration * sampleRate)
        guard frameCount > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount),
              let channel = buffer.floatChannelData?[0]
        else { return nil }

        buffer.frameLength = frameCount

        let tones = effect.tones
        let segment = Float(frameCount) / Float(tones.count)
        var phase: Float = 0

        for frame in 0..<Int(frameCount) {
            let toneIndex = min(tones.count - 1, Int(Float(frame) / segment))
            let frequency = tones[toneIndex]
            phase += 2 * .pi * frequency / sampleRate
            if phase > 2 * .pi { phase -= 2 * .pi }

            let raw: Float = effect.isSquare
                ? (sin(phase) >= 0 ? 1 : -1)
                : (2 / .pi) * asin(sin(phase))

            // Short attack, exponential decay — stops clicks at the edges.
            let progress = Float(frame) / Float(frameCount)
            let attack = min(1, progress / 0.06)
            let decay = expf(-3.2 * progress)
            channel[frame] = raw * effect.amplitude * attack * decay
        }

        return buffer
    }
}
