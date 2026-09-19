import CoreGraphics
import Foundation
import CryptoKit

/// Local mirror of the server's daily-challenge derivation.
///
/// The algorithm is identical to `backend/src/domain/challenge.ts`: SHA-256 of
/// `flappy-bird-daily:<YYYY-MM-DD>` seeds every parameter. That means the game
/// can offer the exact same challenge with no server at all — the backend is
/// only needed to compare scores with other players.
enum DailyChallengeHelper {

    /// Resolved parameters for a run.
    struct Challenge: Equatable {
        var date: String
        var seed: String
        var mode: GameMode
        var pipeGap: CGFloat
        var gravityScale: CGFloat
        var speedScale: CGFloat
        var modifier: String
        var summary: String
    }

    private static let modifiers = ["none", "windy", "foggy", "nightfall", "narrow", "turbo"]
    private static let modes: [GameMode] = [.classic, .endless, .timeAttack, .hardcore]

    /// `YYYY-MM-DD` in UTC — the same rollover the server uses.
    static func todayKey(now: Date = Date()) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        let parts = calendar.dateComponents([.year, .month, .day], from: now)
        return String(format: "%04d-%02d-%02d", parts.year ?? 1970, parts.month ?? 1, parts.day ?? 1)
    }

    static func derive(for dateKey: String) -> Challenge {
        let digest = Array(SHA256.hash(data: Data("flappy-bird-daily:\(dateKey)".utf8)))

        func byte(_ index: Int) -> Int { Int(digest[index % digest.count]) }

        let mode = modes[byte(0) % modes.count]
        let modifier = modifiers[byte(1) % modifiers.count]
        let pipeGap = CGFloat(110 + (byte(2) % 7) * 10)
        // Rounded to two decimals to match the server's `toFixed(2)`.
        let gravityScale = CGFloat(((0.85 + Double(byte(3) % 7) * 0.05) * 100).rounded() / 100)
        let speedScale = CGFloat(((0.90 + Double(byte(4) % 9) * 0.05) * 100).rounded() / 100)
        let seed = digest.prefix(8).map { String(format: "%02x", $0) }.joined()

        return Challenge(
            date: dateKey,
            seed: seed,
            mode: mode,
            pipeGap: pipeGap,
            gravityScale: gravityScale,
            speedScale: speedScale,
            modifier: modifier,
            summary: summary(mode: mode, modifier: modifier, pipeGap: pipeGap, speedScale: speedScale)
        )
    }

    /// Prefer the server's copy when available, falling back to local derivation.
    static func resolve(remote: APIDailyChallenge?) -> Challenge {
        guard let remote else { return derive(for: todayKey()) }
        return Challenge(
            date: remote.date,
            seed: remote.seed,
            mode: GameMode(rawValue: remote.mode) ?? .classic,
            pipeGap: CGFloat(remote.pipeGap),
            gravityScale: CGFloat(remote.gravityScale),
            speedScale: CGFloat(remote.speedScale),
            modifier: remote.modifier,
            summary: remote.description
        )
    }

    private static func summary(
        mode: GameMode,
        modifier: String,
        pipeGap: CGFloat,
        speedScale: CGFloat
    ) -> String {
        var parts = ["\(mode.displayName) run"]
        if pipeGap <= 125 {
            parts.append("tight gaps")
        } else if pipeGap >= 160 {
            parts.append("generous gaps")
        }
        if speedScale >= 1.2 { parts.append("fast scroll") }
        if modifier != "none" { parts.append(modifier) }
        return "Today: " + parts.joined(separator: ", ") + "."
    }

    /// Weather implied by a challenge modifier.
    static func weather(for modifier: String) -> Weather? {
        switch modifier {
        case "windy": return .windy
        case "foggy": return .fog
        default: return nil
        }
    }
}
