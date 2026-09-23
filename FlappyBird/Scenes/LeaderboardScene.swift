import SpriteKit

/// Global leaderboards, with a local fallback when no server is reachable.
final class LeaderboardScene: ListScene {

    private let windows = ["all", "daily", "weekly", "monthly"]
    private var loadTask: Task<Void, Never>?
    private var statusToken: UUID?
    /// Tracks the last connection state rendered, so the list is only rebuilt
    /// when it actually changes.
    private var renderedOnline: Bool?

    override var screenTitle: String { "LEADERBOARD" }
    override var segments: [String] { ["ALL TIME", "TODAY", "WEEK", "MONTH"] }
    override var rowHeight: CGFloat { 48 }

    override func didMove(to view: SKView) {
        super.didMove(to: view)

        // Discovery runs in the background, so opening this screen moments after
        // launch would otherwise show local scores forever — the guard in
        // `buildContent()` sees `.searching` and never looks again.
        statusToken = OnlineService.shared.observeStatus { [weak self] status in
            guard let self, self.renderedOnline != status.isOnline else { return }
            self.buildContent()
        }
    }

    override func willMove(from view: SKView) {
        loadTask?.cancel()
        if let statusToken { OnlineService.shared.removeObserver(statusToken) }
    }

    override func buildContent() {
        loadTask?.cancel()
        renderedOnline = OnlineService.shared.status.isOnline

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
        let service = OnlineService.shared
        let me = service.username
        var rows: [SKNode] = []

        // Make the leaderboard identity explicit. On first contact the backend
        // creates a device-bound guest (for example `guest_ab12cd`); players can
        // claim that same profile from Settings → Server without losing scores.
        if let me {
            rows.append(makeRow(
                badge: "👤",
                title: "Playing as @\(me)",
                subtitle: service.isGuest
                    ? "Guest · claim in Settings → Server"
                    : "Account · ranked runs upload here",
                value: "YOU",
                valueColor: Palette.positive,
                highlighted: true
            ))
        }

        guard !page.items.isEmpty else {
            guard !rows.isEmpty else {
                showStatus("No scores in this window yet.\nBe the first!")
                return
            }

            rows.append(makeRow(
                badge: "🏁",
                title: "No ranked score yet",
                subtitle: "Finish a ranked run to join this board",
                value: ""
            ))
            setRows(rows)
            return
        }

        rows += page.items.map { entry -> SKNode in
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
