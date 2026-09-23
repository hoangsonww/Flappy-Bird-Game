import Foundation

/// Launch-argument switches used by tooling.
///
/// These exist so the screenshots in the README and on the landing page can be
/// produced deterministically from the command line — no manual tapping, no
/// flaky UI automation:
///
/// ```bash
/// xcrun simctl launch <udid> com.hoangsonww.flappybird -screen shop -seed-demo
/// xcrun simctl launch <udid> com.hoangsonww.flappybird -demo -seed-demo
/// ```
///
/// Nothing here changes behaviour for a normal launch.
enum LaunchOptions {

    private static let arguments = ProcessInfo.processInfo.arguments

    /// Auto-pilot: the bird plays itself. Used for automated media captures.
    static var isDemoMode: Bool { arguments.contains("-demo") }

    /// Populate the local profile with believable progress so capture screens
    /// are not empty. Only ever applied when explicitly requested.
    static var shouldSeedDemoData: Bool { arguments.contains("-seed-demo") }

    /// Overlay live gameplay numbers (state, velocity, target gap). Useful when
    /// tuning the flight model or diagnosing a capture that does not look right.
    static var showsDebugOverlay: Bool { arguments.contains("-debug-hud") }

    /// End an attract-mode run after this many seconds (`-demo-die 6`).
    ///
    /// The summary panel is otherwise only reachable by waiting for the
    /// auto-pilot to crash, and how long that takes is exactly as variable as
    /// the flight model — the capture either caught the panel or missed it
    /// depending on the run. This makes it a cue rather than a race.
    static var demoDeathDelay: TimeInterval? {
        guard let index = arguments.firstIndex(of: "-demo-die"),
              arguments.indices.contains(index + 1),
              let seconds = TimeInterval(arguments[index + 1]),
              seconds > 0
        else { return nil }
        return seconds
    }

    /// Skip the menu and open a specific screen.
    static var initialScreen: Screen? {
        guard let index = arguments.firstIndex(of: "-screen"),
              arguments.indices.contains(index + 1)
        else { return nil }
        return Screen(rawValue: arguments[index + 1].lowercased())
    }

    /// Force a game mode (`-mode hardcore`), overriding the saved selection.
    static var forcedMode: GameMode? {
        guard let index = arguments.firstIndex(of: "-mode"),
              arguments.indices.contains(index + 1)
        else { return nil }
        return GameMode(rawValue: arguments[index + 1])
    }

    /// Pre-select a filter chip on a list screen (`-segment 2`).
    static var initialSegment: Int? {
        guard let index = arguments.firstIndex(of: "-segment"),
              arguments.indices.contains(index + 1)
        else { return nil }
        return Int(arguments[index + 1])
    }

    /// Open the account sheet directly so XCUITest can verify real keyboard
    /// entry without requiring a live backend to manufacture a guest first.
    static var showsAccountFormForUITesting: Bool {
        arguments.contains("-ui-testing") && arguments.contains("-show-account-form")
    }

    enum Screen: String {
        case menu
        case game
        case leaderboard
        case achievements
        case shop
        case stats
        case settings
    }

    /// Fill the store with a plausible history: a few dozen runs, some coins,
    /// unlocked skins and a mix of earned achievements.
    static func seedDemoDataIfRequested(
        store: GameStore = .shared,
        settings: Settings = .shared
    ) {
        guard shouldSeedDemoData else { return }

        store.resetProgress()

        var generator = SeededRandom(seed: 20_260_319)
        let modes: [GameMode] = [.classic, .endless, .timeAttack, .hardcore]

        for index in 0..<36 {
            let mode = modes[generator.nextInt(in: 0...(modes.count - 1))]
            let score = generator.nextInt(in: 4...68)

            var run = RunStats()
            run.score = score
            run.pipesPassed = score
            run.coins = generator.nextInt(in: 0...score)
            run.maxCombo = generator.nextInt(in: 0...max(1, score / 3))
            run.powerUpsUsed = generator.nextInt(in: 0...3)
            run.sawNight = score > 40
            run.seed = SeededRandom.newSeedString()
            run.startedAt = Date().addingTimeInterval(TimeInterval(-index * 900))
            run.endedAt = run.startedAt.addingTimeInterval(Double(score) * 1.2 + 4)

            _ = store.record(run: run, mode: mode, deathCause: index.isMultiple(of: 3) ? .ground : .pipe)
            _ = AchievementSystem(store: store).evaluate(run: run, mode: mode)
        }

        store.update { profile in
            profile.wallet = 1_450
            profile.unlockedSkins.formUnion([
                BirdSkin.mint.rawValue,
                BirdSkin.ember.rawValue,
                BirdSkin.midnight.rawValue,
                BirdSkin.royal.rawValue,
            ])

            // Demo history is a capture fixture, not real play. `record` queues
            // every run for upload, so without this a seeded launch pushes 36
            // fabricated runs onto a real leaderboard — and 36 at once trips the
            // server's submission-rate heuristic, whose toast then lands in the
            // middle of the screenshot being taken.
            profile.pendingUploads.removeAll()
            for index in profile.recentRuns.indices {
                profile.recentRuns[index].synced = true
            }
        }

        for day in 1...5 {
            store.markDailyCompleted(String(format: "2026-03-%02d", day))
        }

        // Classic on purpose: the seeded profile is what screenshots and the
        // capture script show, and that should be the yellow bird the game
        // ships with, not one of the unlocked recolours.
        settings.selectedSkin = .classic
        settings.showFPS = false
        // The selected mode survives in `UserDefaults` across launches, so
        // without this a seeded launch inherits whatever the *last* launch left
        // behind — a UI test that ran with `-mode zen`, or a mode-cycling test
        // that stopped on Daily. Seeding means "a known profile", so the mode
        // is part of what it resets.
        settings.selectedMode = .classic
        settings.hasSeenTutorial = true
    }
}

/// A tiny auto-pilot used by `-demo`.
///
/// The flight model is deliberately twitchy — one flap lifts the bird roughly
/// 90 points — so a naive "flap when below the centre" controller overshoots the
/// top pipe. Instead the pilot aims low in the gap and lets the arc of a single
/// flap carry it back up, which keeps the bird inside a band that fits the
/// opening.
struct DemoPilot {

    /// Minimum seconds between flaps, so it cannot machine-gun the impulse.
    private let flapCooldown: TimeInterval = 0.12
    /// Never add lift while already climbing this fast.
    private let risingThreshold: CGFloat = 110
    /// How far below the gap centre to aim, capped for very tight gaps.
    private let aimBelowCentre: CGFloat = 45

    private var lastFlap: TimeInterval = -.greatestFiniteMagnitude

    /// Clear the cooldown clock. Scene time restarts at zero on every run, so a
    /// stale timestamp would otherwise leave the pilot permanently on cooldown.
    mutating func reset() {
        lastFlap = -.greatestFiniteMagnitude
    }

    /// Decide whether to flap this frame.
    ///
    /// - Parameters:
    ///   - birdY: the bird's current height.
    ///   - gapCentre: centre of the opening it is aiming for.
    ///   - gapHeight: height of that opening.
    ///   - verticalVelocity: current vertical speed.
    ///   - now: scene time, in seconds since the run started.
    mutating func shouldFlap(
        birdY: CGFloat,
        gapCentre: CGFloat,
        gapHeight: CGFloat,
        verticalVelocity: CGFloat,
        now: TimeInterval
    ) -> Bool {
        guard now - lastFlap >= flapCooldown else { return false }
        // Already climbing: another flap would overshoot the top of the gap.
        guard verticalVelocity < risingThreshold else { return false }

        let target = gapCentre - min(aimBelowCentre, gapHeight * 0.32)
        guard birdY < target else { return false }

        lastFlap = now
        return true
    }
}
