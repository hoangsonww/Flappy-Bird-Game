import SpriteKit

/// Global leaderboards, with a local fallback when no server is reachable.
final class LeaderboardScene: ListScene {

    private let windows = ["all", "daily", "weekly", "monthly"]
    private var loadTask: Task<Void, Never>?

    override var screenTitle: String { "LEADERBOARD" }
    override var segments: [String] { ["ALL TIME", "TODAY", "WEEK", "MONTH"] }
    override var rowHeight: CGFloat { 48 }

    override func willMove(from view: SKView) {
        loadTask?.cancel()
    }

    override func buildContent() {
        loadTask?.cancel()

        guard OnlineService.shared.status.isOnline else {
            showLocalScores()
            return
        }

        showStatus("Loading…")
        let window = windows[min(selectedSegment, windows.count - 1)]

        loadTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let page = try await OnlineService.shared.leaderboard(
                    mode: nil,
                    window: window,
                    limit: 50
                )
                guard !Task.isCancelled else { return }
                self.render(page: page)
            } catch {
                guard !Task.isCancelled else { return }
                let message = (error as? APIError)?.errorDescription ?? error.localizedDescription
                self.showStatus("Could not load the leaderboard.\n\(message)\n\nShowing your local scores instead.")
                self.showLocalScores(keepStatus: true)
            }
        }
    }

    private func render(page: LeaderboardPage) {
        guard !page.items.isEmpty else {
            showStatus("No scores in this window yet.\nBe the first!")
            return
        }

        let me = OnlineService.shared.username
        let rows = page.items.map { entry -> SKNode in
            makeRow(
                badge: medalBadge(for: entry.rank),
                title: entry.displayName,
                subtitle: "@\(entry.username)\(entry.country.map { " · \($0)" } ?? "") · \(entry.mode)",
                value: String(entry.score),
                valueColor: entry.rank <= 3 ? Palette.accent : Palette.primaryText,
                highlighted: entry.username == me
            )
        }
        setRows(rows)
    }

    /// Offline view: the player's own recent runs, ranked locally.
    private func showLocalScores(keepStatus: Bool = false) {
        let runs = GameStore.shared.profile.recentRuns
            .sorted { $0.score > $1.score }
            .prefix(25)

        guard !runs.isEmpty else {
            showStatus(
                OnlineService.shared.status.isOnline
                    ? "No scores yet — go play a round!"
                    : "No server connected, so this shows your local scores.\n\nPlay a round to fill it in."
            )
            return
        }

        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short

        let rows = runs.enumerated().map { index, run -> SKNode in
            makeRow(
                badge: medalBadge(for: index + 1),
                title: run.mode.displayName,
                subtitle: "\(formatter.string(from: run.date)) · \(run.pipesPassed) pipes",
                value: String(run.score),
                valueColor: index < 3 ? Palette.accent : Palette.primaryText
            )
        }

        if keepStatus {
            scroll.setRows(rows, rowHeight: rowHeight)
        } else {
            setRows(rows)
        }
    }

    private func medalBadge(for rank: Int) -> String {
        switch rank {
        case 1: return "🥇"
        case 2: return "🥈"
        case 3: return "🥉"
        default: return "#\(rank)"
        }
    }
}
