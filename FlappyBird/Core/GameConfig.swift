import CoreGraphics
import SpriteKit

/// Physics categories shared by every node in the scene.
///
/// Kept as an `OptionSet` so collision masks read as sets rather than bit soup.
struct PhysicsCategory: OptionSet {
    let rawValue: UInt32

    static let bird     = PhysicsCategory(rawValue: 1 << 0)
    static let world    = PhysicsCategory(rawValue: 1 << 1)
    static let pipe     = PhysicsCategory(rawValue: 1 << 2)
    static let scoreGate = PhysicsCategory(rawValue: 1 << 3)
    static let coin     = PhysicsCategory(rawValue: 1 << 4)
    static let powerUp  = PhysicsCategory(rawValue: 1 << 5)
    static let ceiling  = PhysicsCategory(rawValue: 1 << 6)
}

/// Z-ordering. Explicit constants beat scattered magic numbers.
enum ZPosition {
    static let sky: CGFloat = -30
    static let clouds: CGFloat = -25
    static let distantCity: CGFloat = -20
    static let pipes: CGFloat = -10
    static let ground: CGFloat = 5
    static let ghost: CGFloat = 8
    static let collectible: CGFloat = 10
    static let bird: CGFloat = 20
    static let particles: CGFloat = 25
    static let weather: CGFloat = 40
    static let hud: CGFloat = 100
    static let overlay: CGFloat = 200
    static let toast: CGFloat = 300
}

/// Tunable gameplay constants.
///
/// Everything the designer might want to tweak lives here, so balance changes
/// never require hunting through scene code.
enum GameConfig {

    // MARK: - Physics

    /// Base gravity. Modes and daily challenges scale this.
    static let gravity: CGFloat = -5.0
    /// Upward impulse applied per tap.
    static let flapImpulse: CGFloat = 30.0
    /// Explicit body mass for the bird.
    ///
    /// SpriteKit derives mass from the body's area, so shrinking the hitbox to be
    /// forgiving would otherwise make every flap launch the bird much higher.
    /// Pinning the mass keeps the original tuning (impulse 30 on a 24pt radius)
    /// independent of how generous the collision shape is.
    static let birdMass: CGFloat = 0.0804
    /// Terminal downward velocity, so a long fall stays readable.
    static let maxFallSpeed: CGFloat = -900
    /// Terminal upward velocity, so tap-spamming cannot launch the bird offscreen.
    static let maxRiseSpeed: CGFloat = 520

    // MARK: - World

    static let pipeScale: CGFloat = 2.0
    static let groundScale: CGFloat = 2.0
    static let birdScale: CGFloat = 2.0

    /// Vertical gap between pipes at the easiest difficulty.
    static let baseVerticalPipeGap: CGFloat = 155
    /// Smallest gap the difficulty curve will ever produce.
    static let minimumVerticalPipeGap: CGFloat = 104
    /// Seconds between pipe spawns at the easiest difficulty.
    static let baseSpawnInterval: TimeInterval = 1.9
    static let minimumSpawnInterval: TimeInterval = 1.05
    /// Seconds a pipe takes to cross one point of horizontal distance.
    static let baseScrollRate: TimeInterval = 0.010
    static let fastestScrollRate: TimeInterval = 0.0062

    // MARK: - Scoring

    /// Points awarded for clearing a pipe.
    static let pointsPerPipe = 1
    /// Coins awarded for a collected coin, before the combo multiplier.
    static let coinValue = 1
    /// Combo multiplier is capped so the score stays believable.
    static let maxComboMultiplier = 8
    /// Pipes cleared between day/night transitions.
    static let pipesPerDayNightCycle = 20

    // MARK: - Power-ups

    /// Probability that a pipe gap contains a power-up instead of a coin.
    static let powerUpSpawnChance = 0.14
    static let shieldDuration: TimeInterval = 0
    static let slowMotionDuration: TimeInterval = 5.0
    static let slowMotionFactor: CGFloat = 0.55
    static let magnetDuration: TimeInterval = 8.0
    static let magnetRadius: CGFloat = 170
    static let doublePointsDuration: TimeInterval = 10.0
    static let shrinkDuration: TimeInterval = 8.0
    static let shrinkFactor: CGFloat = 0.65

    // MARK: - Modes

    static let timeAttackDuration: TimeInterval = 60

    // MARK: - Ghost replay

    /// Sampling interval for the ghost recorder, in seconds.
    static let ghostSampleInterval: TimeInterval = 1.0 / 20.0
    /// Hard cap on recorded samples (~5 minutes at 20 Hz) to bound storage.
    static let ghostMaxSamples = 6_000

    // MARK: - Presentation

    static let deathFlashCount = 4
    static let deathFlashInterval: TimeInterval = 0.05
    static let toastDuration: TimeInterval = 2.2
}

/// Medal tiers awarded on the game-over panel.
enum Medal: String, CaseIterable {
    case none, bronze, silver, gold, platinum

    /// Score needed to earn the tier.
    var threshold: Int {
        switch self {
        case .none: return 0
        case .bronze: return 10
        case .silver: return 25
        case .gold: return 50
        case .platinum: return 100
        }
    }

    var label: String {
        switch self {
        case .none: return "—"
        case .bronze: return "Bronze"
        case .silver: return "Silver"
        case .gold: return "Gold"
        case .platinum: return "Platinum"
        }
    }

    var color: SKColor {
        switch self {
        case .none: return SKColor(white: 0.55, alpha: 1)
        case .bronze: return SKColor(red: 0.80, green: 0.50, blue: 0.20, alpha: 1)
        case .silver: return SKColor(red: 0.78, green: 0.80, blue: 0.84, alpha: 1)
        case .gold: return SKColor(red: 0.98, green: 0.79, blue: 0.24, alpha: 1)
        case .platinum: return SKColor(red: 0.62, green: 0.88, blue: 0.95, alpha: 1)
        }
    }

    /// Highest tier earned for a score.
    static func earned(for score: Int) -> Medal {
        allCases.last { score >= $0.threshold && $0 != .none } ?? .none
    }
}
