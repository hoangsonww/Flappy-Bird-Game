import SpriteKit

/// The saved recordings, newest first.
final class ReplaysScene: ListScene {

    override var screenTitle: String { "REPLAYS" }
    override var rowHeight: CGFloat { 56 }

    private let store: ReplayStore

    init(size: CGSize, store: ReplayStore = .shared) {
        self.store = store
        super.init(size: size)
    }

    @available(*, unavailable)
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func buildContent() {
        let replays = store.replays
        guard !replays.isEmpty else {
            setRows([])
            showStatus("No replays yet.\nEvery run you finish is recorded here.")
            return
        }

        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("Mdjm")

        let rows = replays.map { replay -> SKNode in
            makeReplayRow(replay, subtitle: formatter.string(from: replay.recordedAt))
        }
        setRows(rows)
    }

    /// A row that opens the replay when tapped.
    ///
    /// `ListScene.makeRow` builds a static row; a replay needs the whole row to
    /// be the control, so the button spans it and the text is drawn on top.
    private func makeReplayRow(_ replay: Replay, subtitle: String) -> SKNode {
        let row = SKNode()
        let width = contentWidth - 8

        let button = ButtonNode(
            title: "",
            size: CGSize(width: width, height: rowHeight - 6),
            fillColor: SKColor(white: 1, alpha: 0.05),
            borderColor: SKColor(white: 1, alpha: 0.12)
        ) { [weak self] in
            self?.open(replay)
        }
        button.accessibilityLabel = accessibilitySentence(
            "\(replay.score) points",
            replay.mode.displayName,
            subtitle,
            String(format: "%.0f seconds", replay.duration)
        )
        row.addChild(button)

        let left = -width / 2 + 16

        let badge = SKLabelNode(fontNamed: Fonts.body)
        badge.text = replay.mode.symbol
        badge.fontSize = 17
        badge.horizontalAlignmentMode = .left
        badge.verticalAlignmentMode = .center
        badge.position = CGPoint(x: left, y: 0)
        row.addChild(badge)

        let title = SKLabelNode(fontNamed: Fonts.display)
        title.text = "\(replay.score) pts"
        title.fontSize = 16
        title.fontColor = Palette.primaryText
        title.horizontalAlignmentMode = .left
        title.verticalAlignmentMode = .center
        title.position = CGPoint(x: left + 34, y: 8)
        row.addChild(title)

        let detail = SKLabelNode(fontNamed: Fonts.body)
        detail.text = "\(replay.mode.displayName) · \(subtitle)"
        detail.fontSize = 11
        detail.fontColor = Palette.secondaryText
        detail.horizontalAlignmentMode = .left
        detail.verticalAlignmentMode = .center
        detail.position = CGPoint(x: left + 34, y: -9)
        row.addChild(detail)

        let length = SKLabelNode(fontNamed: Fonts.display)
        length.text = String(format: "%.0fs", replay.duration)
        length.fontSize = 15
        length.fontColor = Palette.accent
        length.horizontalAlignmentMode = .right
        length.verticalAlignmentMode = .center
        length.position = CGPoint(x: width / 2 - 16, y: 0)
        row.addChild(length)

        return row
    }

    private func open(_ replay: Replay) {
        let scene = ReplayScene(size: size, replay: replay)
        scene.scaleMode = .resizeFill
        view?.presentScene(scene, transition: .push(with: .left, duration: 0.3))
    }
}
