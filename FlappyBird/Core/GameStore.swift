import Foundation

/// A finished run, as stored locally.
struct RunRecord: Codable, Equatable {
    var score: Int
    var mode: GameMode
    var coins: Int
    var pipesPassed: Int
    var durationMs: Int
    var maxCombo: Int
    var powerUpsUsed: Int
    var seed: String
    var date: Date
    /// `false` until the backend has acknowledged it.
    var synced: Bool

    init(
        score: Int,
        mode: GameMode,
        coins: Int,
        pipesPassed: Int,
        durationMs: Int,
        maxCombo: Int,
        powerUpsUsed: Int,
        seed: String,
        date: Date = Date(),
        synced: Bool = false
    ) {
        self.score = score
        self.mode = mode
        self.coins = coins
        self.pipesPassed = pipesPassed
        self.durationMs = durationMs
        self.maxCombo = maxCombo
        self.powerUpsUsed = powerUpsUsed
        self.seed = seed
        self.date = date
        self.synced = synced
    }
}

/// Lifetime totals shown on the stats screen.
struct LifetimeStats: Codable, Equatable {
    var gamesPlayed = 0
    var totalScore = 0
    var totalCoins = 0
    var totalPipes = 0
    var totalDurationMs = 0
    var longestRunMs = 0
    var bestCombo = 0
    var deathsByPipe = 0
    var deathsByGround = 0
    var powerUpsCollected = 0
    var nightRuns = 0

    var averageScore: Double {
        gamesPlayed == 0 ? 0 : Double(totalScore) / Double(gamesPlayed)
    }

    var totalPlayTime: TimeInterval { Double(totalDurationMs) / 1000 }
}

/// Everything persisted about the player, in one `Codable` document.
struct PlayerProfile: Codable, Equatable {
    var bestScores: [String: Int] = [:]
    var wallet = 0
    var unlockedSkins: Set<String> = [BirdSkin.classic.rawValue]
    var achievements: [String: AchievementProgress] = [:]
    var stats = LifetimeStats()
    var recentRuns: [RunRecord] = []
    var pendingUploads: [RunRecord] = []
    var dailyChallengesCompleted: [String] = []
    var ghostSamples: [Double] = []
    var ghostScore = 0

    func bestScore(for mode: GameMode) -> Int { bestScores[mode.rawValue] ?? 0 }

    var overallBest: Int { bestScores.values.max() ?? 0 }
}

/// Locally tracked achievement progress, mirroring the server's shape.
struct AchievementProgress: Codable, Equatable {
    var progress: Int
    var unlockedAt: Date?

    var isUnlocked: Bool { unlockedAt != nil }
}

/// Persistent player data with a JSON document in `UserDefaults`.
///
/// One document keeps reads/writes atomic and makes the whole profile trivially
/// exportable — which is exactly what the backend sync needs.
final class GameStore {
    static let shared = GameStore(defaults: .standard)

    private let defaults: UserDefaults
    private let storageKey = "player.profile.v2"
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    /// Cached in memory; the scene reads this many times per frame.
    private(set) var profile: PlayerProfile

    /// Maximum locally retained runs. Older entries are dropped.
    private let recentRunLimit = 50
    /// Cap on queued uploads so an offline player cannot grow storage forever.
    private let pendingUploadLimit = 200

    init(defaults: UserDefaults) {
        self.defaults = defaults
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601

        if let data = defaults.data(forKey: storageKey),
           let decoded = try? decoder.decode(PlayerProfile.self, from: data) {
            profile = decoded
        } else {
            profile = PlayerProfile()
        }
    }

    // MARK: - Persistence

    private func save() {
        guard let data = try? encoder.encode(profile) else { return }
        defaults.set(data, forKey: storageKey)
    }

    /// Mutate and persist in one step.
    func update(_ mutate: (inout PlayerProfile) -> Void) {
        mutate(&profile)
        save()
    }

    // MARK: - Runs

    /// Record a finished run. Returns `true` when it beat the mode's best score.
    @discardableResult
    func record(run: RunStats, mode: GameMode, deathCause: DeathCause) -> Bool {
        let record = RunRecord(
            score: run.score,
            mode: mode,
            coins: run.coins,
            pipesPassed: run.pipesPassed,
            durationMs: run.durationMs,
            maxCombo: run.maxCombo,
            powerUpsUsed: run.powerUpsUsed,
            seed: run.seed,
            synced: false
        )

        var isPersonalBest = false

        update { profile in
            if run.score > profile.bestScore(for: mode) {
                profile.bestScores[mode.rawValue] = run.score
                isPersonalBest = true
            }

            profile.wallet += run.coins
            profile.stats.gamesPlayed += 1
            profile.stats.totalScore += run.score
            profile.stats.totalCoins += run.coins
            profile.stats.totalPipes += run.pipesPassed
            profile.stats.totalDurationMs += run.durationMs
            profile.stats.longestRunMs = max(profile.stats.longestRunMs, run.durationMs)
            profile.stats.bestCombo = max(profile.stats.bestCombo, run.maxCombo)
            profile.stats.powerUpsCollected += run.powerUpsUsed
            if run.sawNight { profile.stats.nightRuns += 1 }

            switch deathCause {
            case .pipe: profile.stats.deathsByPipe += 1
            case .ground: profile.stats.deathsByGround += 1
            case .timeUp, .none: break
            }

            profile.recentRuns.insert(record, at: 0)
            if profile.recentRuns.count > recentRunLimit {
                profile.recentRuns.removeLast(profile.recentRuns.count - recentRunLimit)
            }

            // Zen runs are local practice and are never uploaded.
            if mode.isRanked {
                profile.pendingUploads.append(record)
                if profile.pendingUploads.count > pendingUploadLimit {
                    profile.pendingUploads.removeFirst(profile.pendingUploads.count - pendingUploadLimit)
                }
            }
        }

        return isPersonalBest
    }

    /// Drop uploaded runs from the queue **and** flag them in the history.
    ///
    /// Only clearing the queue left `recentRuns` claiming "pending sync" for the
    /// lifetime of the install, because nothing ever flipped `synced`.
    func markUploaded(_ records: [RunRecord]) {
        guard !records.isEmpty else { return }

        func isSameRun(_ a: RunRecord, _ b: RunRecord) -> Bool {
            a.date == b.date && a.score == b.score && a.mode == b.mode
        }

        update { profile in
            profile.pendingUploads.removeAll { pending in
                records.contains { isSameRun($0, pending) }
            }
            for index in profile.recentRuns.indices
                where records.contains(where: { isSameRun($0, profile.recentRuns[index]) }) {
                profile.recentRuns[index].synced = true
            }
        }
    }

    func clearPendingUploads() {
        update { $0.pendingUploads.removeAll() }
    }

    // MARK: - Wallet & skins

    func isUnlocked(_ skin: BirdSkin) -> Bool {
        skin == .classic || profile.unlockedSkins.contains(skin.rawValue)
    }

    /// Spend coins to unlock a skin. Returns `false` when the player cannot afford it.
    @discardableResult
    func purchase(_ skin: BirdSkin) -> Bool {
        guard !isUnlocked(skin), profile.wallet >= skin.price else { return false }
        update { profile in
            profile.wallet -= skin.price
            profile.unlockedSkins.insert(skin.rawValue)
        }
        return true
    }

    // MARK: - Achievements

    func progress(for code: String) -> AchievementProgress {
        profile.achievements[code] ?? AchievementProgress(progress: 0, unlockedAt: nil)
    }

    /// Merge progress monotonically — mirrors the server's sync semantics.
    func setProgress(_ value: Int, unlocked: Bool, for code: String) {
        update { profile in
            let existing = profile.achievements[code] ?? AchievementProgress(progress: 0, unlockedAt: nil)
            profile.achievements[code] = AchievementProgress(
                progress: max(existing.progress, value),
                unlockedAt: existing.unlockedAt ?? (unlocked ? Date() : nil)
            )
        }
    }

    var unlockedAchievementCodes: [String] {
        profile.achievements.filter { $0.value.isUnlocked }.map(\.key)
    }

    // MARK: - Daily challenge

    func markDailyCompleted(_ dateKey: String) {
        update { profile in
            if !profile.dailyChallengesCompleted.contains(dateKey) {
                profile.dailyChallengesCompleted.append(dateKey)
            }
        }
    }

    var dailyChallengeStreakCount: Int { profile.dailyChallengesCompleted.count }

    // MARK: - Ghost replay

    /// Store the flight path of a new best run so it can be replayed as a ghost.
    func storeGhost(samples: [Double], score: Int) {
        guard score > profile.ghostScore else { return }
        update { profile in
            profile.ghostSamples = Array(samples.prefix(GameConfig.ghostMaxSamples))
            profile.ghostScore = score
        }
    }

    var ghost: (samples: [Double], score: Int)? {
        guard !profile.ghostSamples.isEmpty else { return nil }
        return (profile.ghostSamples, profile.ghostScore)
    }

    // MARK: - Maintenance

    /// Wipe all local progress (offered in Settings, and used by tests).
    func resetProgress() {
        profile = PlayerProfile()
        save()
    }
}

/// Why a run ended — drives both stats and the game-over copy.
enum DeathCause {
    case pipe
    case ground
    case timeUp
    case none
}
