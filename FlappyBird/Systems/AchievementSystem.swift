import Foundation

/// One achievement definition.
///
/// This catalog mirrors `backend/src/domain/achievements.ts` exactly, which is
/// what lets the game unlock achievements offline and reconcile later.
struct Achievement: Identifiable, Equatable {
    enum Metric: String {
        case score, coins, games, pipes, combo, special
    }

    let code: String
    let name: String
    let detail: String
    let icon: String
    let points: Int
    let metric: Metric
    let threshold: Int
    let secret: Bool

    var id: String { code }
}

/// Evaluates achievements after every run and reports what was newly unlocked.
enum AchievementCatalog {
    // A reference table that is mirrored field-for-field on the server. One
    // achievement per line is far easier to scan and to diff than 18 blocks of
    // wrapped arguments, so the length limit is waived here and nowhere else.
    // swiftlint:disable line_length
    static let all: [Achievement] = [
        Achievement(code: "first_flight", name: "First Flight", detail: "Pass your first pipe.", icon: "🐣", points: 5, metric: .score, threshold: 1, secret: false),
        Achievement(code: "getting_warm", name: "Getting Warm", detail: "Score 10 in a single run.", icon: "🔥", points: 10, metric: .score, threshold: 10, secret: false),
        Achievement(code: "sky_rookie", name: "Sky Rookie", detail: "Score 25 in a single run.", icon: "🪶", points: 20, metric: .score, threshold: 25, secret: false),
        Achievement(code: "pipe_dreamer", name: "Pipe Dreamer", detail: "Score 50 in a single run.", icon: "🌤️", points: 40, metric: .score, threshold: 50, secret: false),
        Achievement(code: "century", name: "Century Club", detail: "Score 100 in a single run.", icon: "💯", points: 100, metric: .score, threshold: 100, secret: false),
        Achievement(code: "legend", name: "Living Legend", detail: "Score 200 in a single run.", icon: "👑", points: 250, metric: .score, threshold: 200, secret: false),
        Achievement(code: "coin_collector", name: "Coin Collector", detail: "Collect 100 coins in total.", icon: "🪙", points: 15, metric: .coins, threshold: 100, secret: false),
        Achievement(code: "treasury", name: "Treasury", detail: "Collect 1,000 coins in total.", icon: "💰", points: 60, metric: .coins, threshold: 1_000, secret: false),
        Achievement(code: "persistent", name: "Persistent", detail: "Play 50 games.", icon: "🎮", points: 20, metric: .games, threshold: 50, secret: false),
        Achievement(code: "dedicated", name: "Dedicated", detail: "Play 250 games.", icon: "🏅", points: 75, metric: .games, threshold: 250, secret: false),
        Achievement(code: "pipe_marathon", name: "Pipe Marathon", detail: "Pass 1,000 pipes in total.", icon: "🏃", points: 50, metric: .pipes, threshold: 1_000, secret: false),
        Achievement(code: "combo_artist", name: "Combo Artist", detail: "Reach a x10 combo.", icon: "✨", points: 35, metric: .combo, threshold: 10, secret: false),
        Achievement(code: "untouchable", name: "Untouchable", detail: "Reach a x25 combo.", icon: "⚡", points: 90, metric: .combo, threshold: 25, secret: false),
        Achievement(code: "night_owl", name: "Night Owl", detail: "Finish a run during the night cycle.", icon: "🌙", points: 15, metric: .special, threshold: 1, secret: false),
        Achievement(code: "storm_chaser", name: "Storm Chaser", detail: "Survive 30 seconds of wind.", icon: "🌪️", points: 30, metric: .special, threshold: 1, secret: false),
        Achievement(code: "daily_devotee", name: "Daily Devotee", detail: "Complete 7 daily challenges.", icon: "📅", points: 70, metric: .special, threshold: 7, secret: false),
        Achievement(code: "perfect_start", name: "Perfect Start", detail: "Pass 10 pipes without using a power-up.", icon: "🎯", points: 25, metric: .special, threshold: 1, secret: false),
        Achievement(code: "ghost_rider", name: "Ghost Rider", detail: "Beat your own ghost replay.", icon: "👻", points: 45, metric: .special, threshold: 1, secret: true),
    ]
    // swiftlint:enable line_length

    static let totalPoints = all.reduce(0) { $0 + $1.points }

    static func definition(for code: String) -> Achievement? {
        all.first { $0.code == code }
    }
}

/// Runs the catalog against local progress and returns newly unlocked entries.
struct AchievementSystem {
    private let store: GameStore

    init(store: GameStore = .shared) {
        self.store = store
    }

    /// Evaluate everything after a finished run.
    ///
    /// - Returns: achievements unlocked by *this* run, for the toast queue.
    func evaluate(run: RunStats, mode: GameMode) -> [Achievement] {
        let profile = store.profile
        var unlocked: [Achievement] = []

        for achievement in AchievementCatalog.all {
            let previously = store.progress(for: achievement.code).isUnlocked
            let value = currentValue(for: achievement, run: run, mode: mode, profile: profile)
            let reached = value >= achievement.threshold

            store.setProgress(value, unlocked: reached, for: achievement.code)

            if reached && !previously {
                unlocked.append(achievement)
            }
        }

        return unlocked
    }

    private func currentValue(
        for achievement: Achievement,
        run: RunStats,
        mode: GameMode,
        profile: PlayerProfile
    ) -> Int {
        switch achievement.metric {
        case .score:
            return max(profile.overallBest, run.score)
        case .coins:
            return profile.stats.totalCoins
        case .games:
            return profile.stats.gamesPlayed
        case .pipes:
            return profile.stats.totalPipes
        case .combo:
            return max(profile.stats.bestCombo, run.maxCombo)
        case .special:
            return specialValue(for: achievement.code, run: run, mode: mode, profile: profile)
        }
    }

    private func specialValue(
        for code: String,
        run: RunStats,
        mode: GameMode,
        profile: PlayerProfile
    ) -> Int {
        switch code {
        case "night_owl":
            return run.sawNight ? 1 : store.progress(for: code).progress
        case "storm_chaser":
            return run.secondsInWind >= 30 ? 1 : store.progress(for: code).progress
        case "daily_devotee":
            return profile.dailyChallengesCompleted.count
        case "perfect_start":
            return (run.pipesPassed >= 10 && run.powerUpsUsed == 0) ? 1 : store.progress(for: code).progress
        case "ghost_rider":
            return run.beatOwnGhost ? 1 : store.progress(for: code).progress
        default:
            return 0
        }
    }

    /// Progress payload for `POST /v1/achievements/me/sync`.
    func syncPayload() -> [[String: Any]] {
        store.profile.achievements.compactMap { code, progress in
            guard AchievementCatalog.definition(for: code) != nil else { return nil }
            var entry: [String: Any] = ["code": code, "progress": progress.progress]
            if let unlockedAt = progress.unlockedAt {
                entry["unlockedAt"] = ISO8601DateFormatter().string(from: unlockedAt)
            }
            return entry
        }
    }
}
