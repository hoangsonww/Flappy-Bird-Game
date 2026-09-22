import SpriteKit
import UIKit

/// Cosmetic bird variants. Raw values match `BIRD_SKINS` on the backend.
enum BirdSkin: String, CaseIterable, Codable {
    case classic, midnight, ember, mint, royal, glitch, aurora, phoenix

    var displayName: String {
        switch self {
        case .classic: return "Classic"
        case .midnight: return "Midnight"
        case .ember: return "Ember"
        case .mint: return "Mint"
        case .royal: return "Royal"
        case .glitch: return "Glitch"
        case .aurora: return "Aurora"
        case .phoenix: return "Phoenix"
        }
    }

    /// Coins required to unlock. `classic` is always available.
    var price: Int {
        switch self {
        case .classic: return 0
        case .mint: return 150
        case .ember: return 300
        case .midnight: return 500
        case .royal: return 800
        case .aurora: return 1_200
        case .glitch: return 1_800
        case .phoenix: return 2_500
        }
    }

    /// Tint applied to the bird sprite.
    var tint: SKColor {
        switch self {
        case .classic: return .white
        case .midnight: return SKColor(red: 0.30, green: 0.36, blue: 0.75, alpha: 1)
        case .ember: return SKColor(red: 0.95, green: 0.35, blue: 0.16, alpha: 1)
        case .mint: return SKColor(red: 0.36, green: 0.89, blue: 0.70, alpha: 1)
        case .royal: return SKColor(red: 0.55, green: 0.30, blue: 0.85, alpha: 1)
        case .glitch: return SKColor(red: 0.15, green: 0.95, blue: 0.45, alpha: 1)
        case .aurora: return SKColor(red: 0.45, green: 0.85, blue: 0.95, alpha: 1)
        case .phoenix: return SKColor(red: 1.00, green: 0.72, blue: 0.10, alpha: 1)
        }
    }

    /// How strongly the tint replaces the original sprite colours.
    var blend: CGFloat { self == .classic ? 0 : 0.78 }

    /// Colour used for the trail particles behind the bird.
    var trailColor: SKColor { self == .classic ? SKColor(white: 1, alpha: 1) : tint }
}

/// Time-of-day palettes. The world cycles through these as the score climbs.
enum TimeOfDay: Int, CaseIterable {
    case day, sunset, night, dawn

    var next: TimeOfDay { TimeOfDay(rawValue: (rawValue + 1) % TimeOfDay.allCases.count) ?? .day }

    var isDark: Bool { self == .night }

    var skyColor: SKColor {
        switch self {
        case .day: return SKColor(red: 0.318, green: 0.753, blue: 0.788, alpha: 1)
        case .sunset: return SKColor(red: 0.96, green: 0.55, blue: 0.36, alpha: 1)
        case .night: return SKColor(red: 0.06, green: 0.09, blue: 0.22, alpha: 1)
        case .dawn: return SKColor(red: 0.55, green: 0.56, blue: 0.82, alpha: 1)
        }
    }

    /// Multiplicative tint applied to world sprites so pipes and ground match the sky.
    var worldTint: SKColor {
        switch self {
        case .day: return .white
        case .sunset: return SKColor(red: 1.0, green: 0.82, blue: 0.70, alpha: 1)
        case .night: return SKColor(red: 0.42, green: 0.48, blue: 0.72, alpha: 1)
        case .dawn: return SKColor(red: 0.82, green: 0.82, blue: 1.0, alpha: 1)
        }
    }

    var worldTintStrength: CGFloat {
        switch self {
        case .day: return 0
        case .sunset: return 0.35
        case .night: return 0.60
        case .dawn: return 0.30
        }
    }

    var hudTextColor: SKColor { .white }

    var name: String {
        switch self {
        case .day: return "Day"
        case .sunset: return "Sunset"
        case .night: return "Night"
        case .dawn: return "Dawn"
        }
    }
}

/// Shared colours for menus, panels and HUD chrome.
enum Palette {
    static let panel = SKColor(red: 0.07, green: 0.10, blue: 0.16, alpha: 0.92)
    static let panelBorder = SKColor(red: 0.98, green: 0.79, blue: 0.24, alpha: 0.9)
    static let primaryText = SKColor.white
    static let secondaryText = SKColor(white: 0.78, alpha: 1)
    static let accent = SKColor(red: 0.98, green: 0.79, blue: 0.24, alpha: 1)
    static let positive = SKColor(red: 0.36, green: 0.89, blue: 0.55, alpha: 1)
    static let negative = SKColor(red: 0.95, green: 0.35, blue: 0.38, alpha: 1)
    static let buttonFill = SKColor(red: 0.14, green: 0.19, blue: 0.29, alpha: 0.95)
    static let buttonFillActive = SKColor(red: 0.22, green: 0.30, blue: 0.45, alpha: 0.98)

    /// High-contrast overrides used when the accessibility setting is on.
    static func text(highContrast: Bool) -> SKColor {
        highContrast ? .white : primaryText
    }
}

/// Font resolution with graceful fallbacks.
///
/// The project ships no custom font file, so a pixel font is requested first and
/// the best available monospace face is used instead when it is missing. This
/// keeps the retro look on any device without bundling licensed assets.
enum Fonts {
    private static let pixelCandidates = ["VT323", "Press Start 2P", "Silkscreen"]
    private static let monospaceCandidates = ["Menlo-Bold", "Courier-Bold", "CourierNewPS-BoldMT"]

    /// Cached because `UIFont(name:)` misses are surprisingly costly in a loop.
    private static var resolvedDisplay: String = {
        for name in pixelCandidates where UIFont(name: name, size: 12) != nil { return name }
        for name in monospaceCandidates where UIFont(name: name, size: 12) != nil { return name }
        return UIFont.monospacedSystemFont(ofSize: 12, weight: .bold).fontName
    }()

    private static var resolvedBody: String = {
        for name in monospaceCandidates where UIFont(name: name, size: 12) != nil { return name }
        return UIFont.monospacedSystemFont(ofSize: 12, weight: .regular).fontName
    }()

    /// Headline / score font.
    static var display: String { resolvedDisplay }
    /// Body copy and list rows.
    static var body: String { resolvedBody }
}
