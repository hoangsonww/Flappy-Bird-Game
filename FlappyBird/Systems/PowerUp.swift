import CoreGraphics
import Foundation
import SpriteKit

/// The collectible effects that can spawn inside a pipe gap.
enum PowerUpKind: String, CaseIterable, Codable {
    case shield
    case slowMotion
    case magnet
    case doublePoints
    case shrink

    /// One glyph, always.
    ///
    /// Double points used to be `"✖️2"` — two characters, which read as a red
    /// cross next to a digit rather than "times two", and which the HUD then
    /// concatenated with the seconds remaining: eight seconds of double points
    /// rendered as `✖️28`.
    var symbol: String {
        switch self {
        case .shield: return "🛡"
        case .slowMotion: return "⏳"
        case .magnet: return "🧲"
        case .doublePoints: return "⭐️"
        case .shrink: return "🔻"
        }
    }

    var displayName: String {
        switch self {
        case .shield: return "Shield"
        case .slowMotion: return "Slow-Mo"
        case .magnet: return "Coin Magnet"
        case .doublePoints: return "Double Points"
        case .shrink: return "Shrink"
        }
    }

    var color: SKColor {
        switch self {
        case .shield: return SKColor(red: 0.42, green: 0.78, blue: 1.0, alpha: 1)
        case .slowMotion: return SKColor(red: 0.72, green: 0.55, blue: 1.0, alpha: 1)
        case .magnet: return SKColor(red: 1.0, green: 0.45, blue: 0.55, alpha: 1)
        case .doublePoints: return SKColor(red: 0.98, green: 0.79, blue: 0.24, alpha: 1)
        case .shrink: return SKColor(red: 0.36, green: 0.89, blue: 0.55, alpha: 1)
        }
    }

    /// `nil` means the effect lasts until it is consumed (the shield).
    var duration: TimeInterval? {
        switch self {
        case .shield: return nil
        case .slowMotion: return GameConfig.slowMotionDuration
        case .magnet: return GameConfig.magnetDuration
        case .doublePoints: return GameConfig.doublePointsDuration
        case .shrink: return GameConfig.shrinkDuration
        }
    }

    /// Relative spawn weight — the shield is the rarest, most valuable pickup.
    var weight: Double {
        switch self {
        case .shield: return 1.0
        case .slowMotion: return 1.6
        case .magnet: return 2.0
        case .doublePoints: return 1.8
        case .shrink: return 1.4
        }
    }

    /// Weighted pick from a seeded generator, so daily runs stay reproducible.
    static func random(using generator: inout SeededRandom) -> PowerUpKind {
        let total = allCases.reduce(0) { $0 + $1.weight }
        var roll = generator.nextDouble(in: 0...total)
        for kind in allCases {
            roll -= kind.weight
            if roll <= 0 { return kind }
        }
        return .magnet
    }
}

/// Tracks which power-ups are active and when they expire.
///
/// The scene asks this for its per-frame modifiers rather than juggling timers.
struct ActivePowerUps {
    private var expiries: [PowerUpKind: TimeInterval] = [:]
    private var shieldCharges = 0

    /// Consumed power-ups this run, reported to the backend.
    private(set) var totalCollected = 0

    mutating func activate(_ kind: PowerUpKind, now: TimeInterval) {
        totalCollected += 1
        if kind == .shield {
            shieldCharges = min(shieldCharges + 1, 2)
            return
        }
        if let duration = kind.duration {
            // Re-collecting extends rather than replaces, which feels generous.
            let base = max(now, expiries[kind] ?? now)
            expiries[kind] = base + duration
        }
    }

    mutating func expire(now: TimeInterval) {
        expiries = expiries.filter { $0.value > now }
    }

    func isActive(_ kind: PowerUpKind, now: TimeInterval) -> Bool {
        if kind == .shield { return shieldCharges > 0 }
        guard let expiry = expiries[kind] else { return false }
        return expiry > now
    }

    func remaining(_ kind: PowerUpKind, now: TimeInterval) -> TimeInterval {
        guard let expiry = expiries[kind] else { return 0 }
        return max(0, expiry - now)
    }

    var hasShield: Bool { shieldCharges > 0 }

    /// Spend one shield charge. Returns `true` when a hit was absorbed.
    mutating func consumeShield() -> Bool {
        guard shieldCharges > 0 else { return false }
        shieldCharges -= 1
        return true
    }

    /// Currently active effects, for the HUD badges.
    func activeKinds(now: TimeInterval) -> [PowerUpKind] {
        var kinds = expiries.filter { $0.value > now }.map(\.key)
        if shieldCharges > 0 { kinds.append(.shield) }
        return kinds.sorted { $0.rawValue < $1.rawValue }
    }

    mutating func reset() {
        expiries.removeAll()
        shieldCharges = 0
        totalCollected = 0
    }
}
