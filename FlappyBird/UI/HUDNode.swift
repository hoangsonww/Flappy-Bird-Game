import SpriteKit

/// The in-run heads-up display.
///
/// Owns the score, combo, coin counter, timer, power-up badges, pause button and
/// online indicator so `GameScene` stays focused on gameplay.
final class HUDNode: SKNode {

    private let sceneSize: CGSize
    private let safeTop: CGFloat

    private let scoreLabel = SKLabelNode()
    private let bestLabel = SKLabelNode()
    private var coinLabel = SKLabelNode()
    private let comboLabel = SKLabelNode()
    private let timerLabel = SKLabelNode()
    private let modeLabel = SKLabelNode()
    private let onlineDot = SKShapeNode(circleOfRadius: 4)
    private let badgeContainer = SKNode()
    private(set) var pauseButton: ButtonNode!

    init(sceneSize: CGSize, safeTop: CGFloat, mode: GameMode, best: Int, onPause: @escaping () -> Void) {
        self.sceneSize = sceneSize
        self.safeTop = safeTop
        super.init()
        zPosition = ZPosition.hud

        let topY = sceneSize.height - safeTop - 28

        // Score — the one element that must be readable at a glance.
        scoreLabel.fontName = Fonts.display
        scoreLabel.fontSize = 46
        scoreLabel.fontColor = .white
        scoreLabel.horizontalAlignmentMode = .center
        scoreLabel.verticalAlignmentMode = .center
        scoreLabel.position = CGPoint(x: sceneSize.width / 2, y: topY - 24)
        scoreLabel.text = "0"
        addShadow(to: scoreLabel)
        addChild(scoreLabel)

        bestLabel.fontName = Fonts.body
        bestLabel.fontSize = 13
        bestLabel.fontColor = Palette.secondaryText
        bestLabel.horizontalAlignmentMode = .center
        bestLabel.verticalAlignmentMode = .center
        bestLabel.position = CGPoint(x: sceneSize.width / 2, y: topY - 56)
        bestLabel.text = "BEST \(best)"
        addChild(bestLabel)

        let coinCounter = CoinIcon.counter(amount: 0, radius: 8, fontSize: 18)
        coinCounter.node.position = CGPoint(x: 26, y: topY)
        addChild(coinCounter.node)
        coinLabel = coinCounter.label

        comboLabel.fontName = Fonts.display
        comboLabel.fontSize = 20
        comboLabel.fontColor = Palette.accent
        comboLabel.horizontalAlignmentMode = .left
        comboLabel.verticalAlignmentMode = .center
        comboLabel.position = CGPoint(x: 18, y: topY - 26)
        comboLabel.text = ""
        addChild(comboLabel)

        modeLabel.fontName = Fonts.body
        modeLabel.fontSize = 12
        modeLabel.fontColor = Palette.secondaryText
        modeLabel.horizontalAlignmentMode = .right
        modeLabel.verticalAlignmentMode = .center
        modeLabel.position = CGPoint(x: sceneSize.width - 60, y: topY - 26)
        modeLabel.text = mode.displayName.uppercased()
        addChild(modeLabel)

        timerLabel.fontName = Fonts.display
        timerLabel.fontSize = 22
        timerLabel.fontColor = .white
        timerLabel.horizontalAlignmentMode = .right
        timerLabel.verticalAlignmentMode = .center
        timerLabel.position = CGPoint(x: sceneSize.width - 60, y: topY)
        timerLabel.isHidden = mode.timeLimit == nil
        addChild(timerLabel)

        onlineDot.fillColor = Palette.secondaryText
        onlineDot.strokeColor = .clear
        onlineDot.position = CGPoint(x: sceneSize.width - 24, y: topY - 44)
        addChild(onlineDot)

        badgeContainer.position = CGPoint(x: 18, y: topY - 54)
        addChild(badgeContainer)

        pauseButton = ButtonNode(
            title: "II",
            size: CGSize(width: 40, height: 40),
            fontSize: 18,
            action: onPause
        )
        pauseButton.position = CGPoint(x: sceneSize.width - 34, y: topY)
        addChild(pauseButton)
    }

    @available(*, unavailable)
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// A dark outline so white text stays legible over a bright sky.
    private func addShadow(to label: SKLabelNode) {
        let shadow = SKLabelNode(fontNamed: label.fontName)
        shadow.fontSize = label.fontSize
        shadow.fontColor = SKColor(white: 0, alpha: 0.35)
        shadow.horizontalAlignmentMode = label.horizontalAlignmentMode
        shadow.verticalAlignmentMode = label.verticalAlignmentMode
        shadow.position = CGPoint(x: 2, y: -2)
        shadow.zPosition = -1
        shadow.name = "shadow"
        label.addChild(shadow)
    }

    // MARK: - Updates

    func setScore(_ score: Int, animated: Bool) {
        scoreLabel.text = String(score)
        (scoreLabel.childNode(withName: "shadow") as? SKLabelNode)?.text = String(score)
        guard animated else { return }
        scoreLabel.run(.sequence([
            .scale(to: 1.28, duration: 0.08),
            .scale(to: 1.0, duration: 0.10),
        ]))
    }

    func setBest(_ best: Int) {
        bestLabel.text = "BEST \(best)"
    }

    func setCoins(_ coins: Int) {
        coinLabel.text = String(coins)
    }

    func setCombo(_ combo: Int, multiplier: Int) {
        if combo >= 2 {
            comboLabel.text = "COMBO x\(multiplier)"
            comboLabel.isHidden = false
            comboLabel.run(.sequence([
                .scale(to: 1.2, duration: 0.06),
                .scale(to: 1.0, duration: 0.08),
            ]))
        } else {
            comboLabel.text = ""
            comboLabel.isHidden = true
        }
    }

    func setTimeRemaining(_ seconds: TimeInterval) {
        timerLabel.isHidden = false
        timerLabel.text = String(format: "%.1fs", max(0, seconds))
        timerLabel.fontColor = seconds <= 10 ? Palette.negative : .white
    }

    func setOnline(_ online: Bool) {
        onlineDot.fillColor = online ? Palette.positive : SKColor(white: 0.4, alpha: 1)
        onlineDot.accessibilityLabel = online ? "Connected to server" : "Offline"
    }

    /// Rebuild the power-up badge row.
    func setActivePowerUps(_ kinds: [PowerUpKind], remaining: (PowerUpKind) -> TimeInterval) {
        badgeContainer.removeAllChildren()

        for (index, kind) in kinds.enumerated() {
            let badge = SKNode()
            badge.position = CGPoint(x: CGFloat(index) * 54, y: 0)

            let pill = SKShapeNode(rectOf: CGSize(width: 48, height: 22), cornerRadius: 11)
            pill.fillColor = kind.color.withAlphaComponent(0.25)
            pill.strokeColor = kind.color
            pill.lineWidth = 1.5
            badge.addChild(pill)

            let text = SKLabelNode(fontNamed: Fonts.body)
            let seconds = remaining(kind)
            text.text = kind == .shield ? kind.symbol : "\(kind.symbol)\(Int(ceil(seconds)))"
            text.fontSize = 12
            text.fontColor = .white
            text.verticalAlignmentMode = .center
            text.horizontalAlignmentMode = .center
            badge.addChild(text)

            badgeContainer.addChild(badge)
        }
    }

    /// Big centre-screen text for "GET READY", "3… 2… 1" and "PAUSED".
    func flashCentreMessage(_ text: String, duration: TimeInterval = 0.8) {
        let label = SKLabelNode(fontNamed: Fonts.display)
        label.text = text
        label.fontSize = 34
        label.fontColor = .white
        label.verticalAlignmentMode = .center
        label.position = CGPoint(x: sceneSize.width / 2, y: sceneSize.height * 0.55)
        label.setScale(0.6)
        label.zPosition = ZPosition.overlay
        addChild(label)

        label.run(.sequence([
            .group([.fadeIn(withDuration: 0.1), .scale(to: 1.0, duration: 0.16)]),
            .wait(forDuration: duration),
            .group([.fadeOut(withDuration: 0.2), .scale(to: 1.15, duration: 0.2)]),
            .removeFromParent(),
        ]))
    }
}
