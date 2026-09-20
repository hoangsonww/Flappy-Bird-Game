import Foundation

/// Lifecycle of a single run.
///
/// ```
///  ready ──tap──▶ playing ──contact──▶ dying ──▶ gameOver ──restart──▶ ready
///                   │  ▲
///            pause  │  │ resume
///                   ▼  │
///                  paused
/// ```
enum GameState: Equatable {
    /// Waiting for the first tap. The bird bobs, the world scrolls, nothing is lethal.
    case ready
    /// Physics and spawning are live.
    case playing
    /// Paused by the player or by the app losing focus.
    case paused
    /// Death animation is running; input is ignored.
    case dying
    /// The summary panel is up and a restart is allowed.
    case gameOver

    var acceptsFlap: Bool { self == .ready || self == .playing }
    var isRunning: Bool { self == .playing }
    var showsOverlay: Bool { self == .paused || self == .gameOver }
}

/// Everything accumulated during one run.
///
/// Deliberately a value type: resetting a run is `stats = RunStats()`.
struct RunStats {
    var score = 0
    var coins = 0
    var pipesPassed = 0
    var maxCombo = 0
    var combo = 0
    var powerUpsUsed = 0
    var startedAt = Date()
    var endedAt: Date?
    var usedShield = false
    var sawNight = false
    var secondsInWind: TimeInterval = 0
    var seed: String = ""

    var duration: TimeInterval {
        (endedAt ?? Date()).timeIntervalSince(startedAt)
    }

    var durationMs: Int {
        max(0, Int((duration * 1000).rounded()))
    }

    /// Score multiplier earned by the current combo, capped by config.
    var comboMultiplier: Int {
        min(max(1, combo), GameConfig.maxComboMultiplier)
    }

    mutating func registerCoin() {
        combo += 1
        maxCombo = max(maxCombo, combo)
        coins += GameConfig.coinValue * comboMultiplier
    }

    mutating func breakCombo() {
        combo = 0
    }
}
