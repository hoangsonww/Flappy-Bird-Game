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

        // A named shape rather than a 3-tuple: the call site below reads better
        // and it keeps the rows self-describing.
        struct Row {
            let badge: String
            let title: String
            let value: String
        }

        let rows: [Row] = [
            Row(badge: "🏆", title: "Best score", value: String(profile.overallBest)),
            Row(badge: "🎮", title: "Games played", value: String(stats.gamesPlayed)),
            Row(badge: "📊", title: "Average score", value: String(format: "%.1f", stats.averageScore)),
            Row(badge: "🪵", title: "Pipes cleared", value: String(stats.totalPipes)),
            Row(badge: "◎", title: "Coins collected", value: String(stats.totalCoins)),
            Row(badge: "◉", title: "Coins in wallet", value: String(profile.wallet)),
            Row(badge: "✨", title: "Best combo", value: "x\(stats.bestCombo)"),
            Row(badge: "⏱", title: "Total play time", value: StatsScene.durationText(stats.totalPlayTime)),
            Row(badge: "🕰", title: "Longest run", value: StatsScene.durationText(Double(stats.longestRunMs) / 1000)),
            Row(badge: "🪵", title: "Deaths by pipe", value: String(stats.deathsByPipe)),
            Row(badge: "🌍", title: "Deaths by ground", value: String(stats.deathsByGround)),
            Row(badge: "⚡️", title: "Power-ups collected", value: String(stats.powerUpsCollected)),
            Row(badge: "🌙", title: "Runs into the night", value: String(stats.nightRuns)),
            Row(badge: "📅", title: "Daily challenges done", value: String(profile.dailyChallengesCompleted.count)),
            Row(badge: "👻", title: "Ghost best", value: profile.ghostScore > 0 ? String(profile.ghostScore) : "—"),
        ]

        setRows(rows.map { makeRow(badge: $0.badge, title: $0.title, subtitle: nil, value: $0.value) })
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
