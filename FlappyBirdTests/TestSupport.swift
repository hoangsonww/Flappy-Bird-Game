import Foundation
import XCTest
@testable import FlappyBird

/// Helpers shared by the unit tests.
///
/// Every test that touches persistence gets its own `UserDefaults` suite so runs
/// stay independent and never clobber the simulator's real save file.
enum TestSupport {

    /// A throwaway defaults suite, cleared before it is handed over.
    ///
    /// `UserDefaults(suiteName:)` only returns nil for a malformed name, which a
    /// UUID never is — but falling back keeps the tests running rather than
    /// crashing the whole bundle if that ever changes.
    static func isolatedDefaults(_ name: String = UUID().uuidString) -> UserDefaults {
        let suite = "com.hoangsonww.flappybird.tests.\(name)"
        guard let defaults = UserDefaults(suiteName: suite) else { return .standard }
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    static func makeStore(_ name: String = UUID().uuidString) -> GameStore {
        GameStore(defaults: isolatedDefaults(name))
    }

    static func makeSettings(_ name: String = UUID().uuidString) -> Settings {
        Settings(defaults: isolatedDefaults(name))
    }

    /// A plausible finished run.
    static func run(
        score: Int,
        coins: Int = 0,
        pipes: Int? = nil,
        combo: Int = 0,
        powerUps: Int = 0,
        sawNight: Bool = false,
        windSeconds: TimeInterval = 0,
        beatGhost: Bool = false,
        durationMs: Int = 30_000
    ) -> RunStats {
        var stats = RunStats()
        stats.score = score
        stats.coins = coins
        stats.pipesPassed = pipes ?? score
        stats.maxCombo = combo
        stats.powerUpsUsed = powerUps
        stats.sawNight = sawNight
        stats.secondsInWind = windSeconds
        stats.beatOwnGhost = beatGhost
        stats.seed = "test-seed"
        stats.startedAt = Date(timeIntervalSince1970: 0)
        stats.endedAt = Date(timeIntervalSince1970: Double(durationMs) / 1000)
        return stats
    }
}
