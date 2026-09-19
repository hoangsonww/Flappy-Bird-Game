import CoreGraphics
import Foundation

/// The rule sets a player can choose from.
///
/// Raw values match the `mode` field accepted by the backend
/// (`GAME_MODES` in `backend/src/config/constants.ts`).
enum GameMode: String, CaseIterable, Codable {
    case classic
    case endless
    case timeAttack
    case hardcore
    case zen
    case daily

    var displayName: String {
        switch self {
        case .classic: return "Classic"
        case .endless: return "Endless"
        case .timeAttack: return "Time Attack"
        case .hardcore: return "Hardcore"
        case .zen: return "Zen"
        case .daily: return "Daily Challenge"
        }
    }

    var subtitle: String {
        switch self {
        case .classic: return "The original rules, steady pace"
        case .endless: return "Difficulty climbs forever"
        case .timeAttack: return "Score as much as you can in 60s"
        case .hardcore: return "Narrow gaps, no power-ups, no mercy"
        case .zen: return "Practice with no game over"
        case .daily: return "Everyone plays the same layout today"
        }
    }

    var symbol: String {
        switch self {
        case .classic: return "🐦"
        case .endless: return "♾️"
        case .timeAttack: return "⏱️"
        case .hardcore: return "💀"
        case .zen: return "🧘"
        case .daily: return "📅"
        }
    }

    /// Whether the difficulty curve ramps as the score grows.
    var ramps: Bool {
        switch self {
        case .classic, .zen: return false
        case .endless, .timeAttack, .hardcore, .daily: return true
        }
    }

    /// Power-ups are disabled in the modes that are meant to be pure.
    var allowsPowerUps: Bool {
        switch self {
        case .hardcore, .daily: return false
        case .classic, .endless, .timeAttack, .zen: return true
        }
    }

    /// Zen mode exists to practise, so contact never ends the run.
    var isLethal: Bool { self != .zen }

    /// Zen runs are local-only: they would distort every leaderboard.
    var isRanked: Bool { self != .zen }

    /// Countdown length, or `nil` for open-ended modes.
    var timeLimit: TimeInterval? {
        self == .timeAttack ? GameConfig.timeAttackDuration : nil
    }

    /// Starting gap between pipes.
    var startingPipeGap: CGFloat {
        switch self {
        case .classic: return GameConfig.baseVerticalPipeGap
        case .endless: return GameConfig.baseVerticalPipeGap
        case .timeAttack: return GameConfig.baseVerticalPipeGap + 10
        case .hardcore: return 118
        case .zen: return GameConfig.baseVerticalPipeGap + 30
        case .daily: return GameConfig.baseVerticalPipeGap
        }
    }

    /// Multiplier applied to the base scroll rate (lower = faster).
    var scrollMultiplier: CGFloat {
        switch self {
        case .classic: return 1.0
        case .endless: return 0.95
        case .timeAttack: return 0.85
        case .hardcore: return 0.8
        case .zen: return 1.15
        case .daily: return 1.0
        }
    }

    var gravityMultiplier: CGFloat {
        switch self {
        case .hardcore: return 1.12
        case .zen: return 0.9
        default: return 1.0
        }
    }

    /// Modes selectable from the main menu, in display order.
    static var selectable: [GameMode] { [.classic, .endless, .timeAttack, .hardcore, .zen, .daily] }
}
