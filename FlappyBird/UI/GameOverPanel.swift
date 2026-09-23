import SpriteKit

/// The end-of-run summary.
///
/// Shows the score, medal, personal-best flag, coins earned, rank (when the
/// backend is reachable) and the restart/menu actions.
final class GameOverPanel: PanelNode {

    struct Summary {
        var score: Int
        var best: Int
        var coins: Int
        var pipesPassed: Int
        var maxCombo: Int
        var duration: TimeInterval
        var mode: GameMode
        var medal: Medal
        var isPersonalBest: Bool
        var cause: DeathCause
        /// Global rank, when the server answered in time.
        var rank: Int?
        var totalPlayers: Int?
        /// Set when the run is queued for upload instead of submitted live.
        var queuedForSync: Bool
        /// Why it was queued, when the server told us something useful.
        var syncDetail: String?
    }

    init(
        summary: Summary,
        width: CGFloat,
        onRetry: @escaping () -> Void,
        onMenu: @escaping () -> Void,
        onShare: (() -> Void)?
    ) {
        let hasRank = summary.rank != nil
        // Derived, not guessed. The old fixed 372/400 were about 26 points
        // short of the content, which pushed the MENU/SHARE row past the
        // panel's own bottom edge — it rendered 2 points *outside* the card.
        let rowCount = hasRank || summary.queuedForSync ? 5 : 4
        let height = GameOverPanel.height(forRows: rowCount)
        super.init(
            size: CGSize(width: width, height: height),
            title: summary.isPersonalBest ? "NEW BEST!" : "GAME OVER",
            titleColor: summary.isPersonalBest ? Palette.positive : Palette.accent
        )

        let contentWidth = width - 56
        var y = contentTop - 8

        // Cause of death, in one friendly line.
        let causeLabel = SKLabelNode(fontNamed: Fonts.body)
        causeLabel.text = GameOverPanel.causeText(summary.cause, mode: summary.mode)
        causeLabel.fontSize = 13
        causeLabel.fontColor = Palette.secondaryText
        causeLabel.verticalAlignmentMode = .center
        causeLabel.position = CGPoint(x: 0, y: y)
        addChild(causeLabel)
        y -= 34

        // Score, big.
        let scoreLabel = SKLabelNode(fontNamed: Fonts.display)
        scoreLabel.text = String(summary.score)
        scoreLabel.fontSize = 58
        scoreLabel.fontColor = .white
        scoreLabel.verticalAlignmentMode = .center
        scoreLabel.position = CGPoint(x: 0, y: y - 12)
        addChild(scoreLabel)
        y -= 58

        // Do not draw an empty medal. The old `.none` variant rendered a ring
        // containing "—", which looked like an unexplained minus button on the
        // game-over panel. A medal is celebratory UI, so it only exists once a
        // tier has actually been earned.
        if summary.medal != .none {
            let medal = MedalNode(medal: summary.medal)
            medal.position = CGPoint(x: -contentWidth / 2 + 38, y: y + 6)
            addChild(medal)
        }

        let bestLabel = SKLabelNode(fontNamed: Fonts.body)
        bestLabel.text = "BEST \(summary.best)"
        bestLabel.fontSize = 14
        bestLabel.fontColor = Palette.secondaryText
        bestLabel.horizontalAlignmentMode = summary.medal == .none ? .center : .right
        bestLabel.verticalAlignmentMode = .center
        bestLabel.position = CGPoint(x: summary.medal == .none ? 0 : contentWidth / 2, y: y + 6)
        addChild(bestLabel)
        y -= 36

        // The row count is decided before layout so the panel can be sized for
        // it; this must produce exactly `rowCount` entries.
        let rows: [(String, String)] = {
            var rows = [
                ("Pipes cleared", String(summary.pipesPassed)),
                ("Coins earned", String(summary.coins)),
                ("Best combo", "x\(summary.maxCombo)"),
                ("Time alive", String(format: "%.1fs", summary.duration)),
            ]
            if let rank = summary.rank {
                let total = summary.totalPlayers ?? 0
                rows.append(("Global rank", total > 0 ? "#\(rank) of \(total)" : "#\(rank)"))
            } else if summary.queuedForSync {
                rows.append(("Cloud sync", summary.syncDetail.map { "queued · \($0)" } ?? "queued"))
            }
            return rows
        }()

        assert(rows.count == rowCount, "The panel was sized for \(rowCount) rows but built \(rows.count)")

        for (label, value) in rows {
            let row = PanelNode.statRow(label: label, value: value, width: contentWidth, fontSize: 14)
            row.position = CGPoint(x: 0, y: y)
            addChild(row)
            y -= GameOverPanel.rowPitch
        }

        y -= 10

        let retry = ButtonNode(title: "PLAY AGAIN", size: CGSize(width: contentWidth, height: 46), action: onRetry)
        retry.position = CGPoint(x: 0, y: y - 8)
        addChild(retry)
        y -= 56

        let secondaryWidth = onShare == nil ? contentWidth : (contentWidth - 10) / 2
        let menu = ButtonNode(
            title: "MENU",
            size: CGSize(width: secondaryWidth, height: 40),
            fontSize: 17,
            action: onMenu
        )
        menu.position = CGPoint(x: onShare == nil ? 0 : -(secondaryWidth + 10) / 2, y: y - 4)
        addChild(menu)

        if let onShare {
            let share = ButtonNode(
                title: "SHARE",
                size: CGSize(width: secondaryWidth, height: 40),
                fontSize: 17,
                action: onShare
            )
            share.position = CGPoint(x: (secondaryWidth + 10) / 2, y: y - 4)
            addChild(share)
        }

        present()
    }

    // MARK: - Geometry

    /// Fixed vertical cost of everything above the stat rows, plus the two
    /// button blocks below them, measured from `PanelNode.contentTop`.
    private static let fixedContentHeight: CGFloat = 226
    /// `PanelNode.contentTop` sits this far below the top edge when titled.
    private static let titleAllowance: CGFloat = 52
    /// Clear space between the last button and the panel's bottom edge.
    private static let bottomPadding: CGFloat = 24
    /// Vertical pitch of one stat row.
    private static let rowPitch: CGFloat = 24

    /// Panel height that leaves `bottomPadding` under the last button.
    static func height(forRows rows: Int) -> CGFloat {
        titleAllowance + fixedContentHeight + CGFloat(rows) * rowPitch + bottomPadding
    }

    private static func causeText(_ cause: DeathCause, mode: GameMode) -> String {
        switch cause {
        case .pipe: return "Clipped a pipe"
        case .ground: return "Hit the ground"
        case .timeUp: return "Time's up!"
        case .none: return mode.displayName
        }
    }
}

/// The medal chip shown on the summary panel.
final class MedalNode: SKNode {
    init(medal: Medal) {
        super.init()

        let ring = SKShapeNode(circleOfRadius: 26)
        ring.fillColor = medal.color.withAlphaComponent(0.22)
        ring.strokeColor = medal.color
        ring.lineWidth = 3
        addChild(ring)

        let label = SKLabelNode(fontNamed: Fonts.body)
        label.text = String(medal.label.prefix(1))
        label.fontSize = 22
        label.fontColor = medal.color
        label.verticalAlignmentMode = .center
        label.horizontalAlignmentMode = .center
        addChild(label)

        let caption = SKLabelNode(fontNamed: Fonts.body)
        caption.text = medal.label.uppercased()
        caption.fontSize = 10
        caption.fontColor = Palette.secondaryText
        caption.verticalAlignmentMode = .center
        caption.position = CGPoint(x: 0, y: -40)
        addChild(caption)

        if medal != .none {
            // A slow shimmer draws the eye to a newly earned medal.
            ring.run(.repeatForever(.sequence([
                .fadeAlpha(to: 0.75, duration: 0.9),
                .fadeAlpha(to: 1.0, duration: 0.9),
            ])))
        }
    }

    @available(*, unavailable)
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
