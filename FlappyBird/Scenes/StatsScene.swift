import SpriteKit

/// Lifetime statistics and per-mode bests.
final class StatsScene: ListScene {

    override var screenTitle: String { "STATS" }
    override var segments: [String] { ["TOTALS", "BY MODE", "RECENT"] }
    override var rowHeight: CGFloat { 44 }

    override func buildContent() {
        switch selectedSegment {
        case 1: showPerMode()
        case 2: showRecentRuns()
        default: showTotals()
        }
    }

    private func showTotals() {
        let profile = GameStore.shared.profile
        let stats = profile.stats

        let rows: [(String, String, String)] = [
            ("🏆", "Best score", String(profile.overallBest)),
            ("🎮", "Games played", String(stats.gamesPlayed)),
            ("📊", "Average score", String(format: "%.1f", stats.averageScore)),
            ("🪵", "Pipes cleared", String(stats.totalPipes)),
            ("◎", "Coins collected", String(stats.totalCoins)),
            ("◉", "Coins in wallet", String(profile.wallet)),
            ("✨", "Best combo", "x\(stats.bestCombo)"),
            ("⏱", "Total play time", StatsScene.durationText(stats.totalPlayTime)),
            ("🕰", "Longest run", StatsScene.durationText(Double(stats.longestRunMs) / 1000)),
            ("🪵", "Deaths by pipe", String(stats.deathsByPipe)),
            ("🌍", "Deaths by ground", String(stats.deathsByGround)),
            ("⚡️", "Power-ups collected", String(stats.powerUpsCollected)),
            ("🌙", "Runs into the night", String(stats.nightRuns)),
            ("📅", "Daily challenges done", String(profile.dailyChallengesCompleted.count)),
            ("👻", "Ghost best", profile.ghostScore > 0 ? String(profile.ghostScore) : "—"),
        ]

        setRows(rows.map { makeRow(badge: $0.0, title: $0.1, subtitle: nil, value: $0.2) })
    }

    private func showPerMode() {
        let profile = GameStore.shared.profile
        let rows = GameMode.selectable.map { mode -> SKNode in
            let best = profile.bestScore(for: mode)
            return makeRow(
                badge: mode.symbol,
                title: mode.displayName,
                subtitle: mode.subtitle,
                value: best > 0 ? String(best) : "—",
                valueColor: best > 0 ? Palette.primaryText : Palette.secondaryText
            )
        }
        setRows(rows)
    }

    private func showRecentRuns() {
        let runs = GameStore.shared.profile.recentRuns
        guard !runs.isEmpty else {
            showStatus("No runs recorded yet.")
            return
        }

        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short

        let rows = runs.map { run -> SKNode in
            makeRow(
                badge: run.mode.symbol,
                title: "\(run.score) pts",
                subtitle: "\(formatter.string(from: run.date)) · \(run.coins)🪙 · x\(run.maxCombo)"
                    + (run.synced ? "" : " · pending sync"),
                value: StatsScene.durationText(Double(run.durationMs) / 1000),
                valueColor: Palette.secondaryText
            )
        }
        setRows(rows)
    }

    /// `1h 04m`, `3m 12s`, `8.4s` — whichever unit reads best.
    static func durationText(_ seconds: TimeInterval) -> String {
        guard seconds > 0 else { return "—" }
        if seconds < 60 { return String(format: "%.1fs", seconds) }
        if seconds < 3_600 {
            return String(format: "%dm %02ds", Int(seconds) / 60, Int(seconds) % 60)
        }
        return String(format: "%dh %02dm", Int(seconds) / 3_600, (Int(seconds) % 3_600) / 60)
    }
}
