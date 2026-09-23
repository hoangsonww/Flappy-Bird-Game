import SpriteKit
import UIKit

/// The main menu.
///
/// Also the app's landing screen: it shows the current mode, personal best,
/// wallet, connection state and the routes into every other screen.
final class MenuScene: SKScene {

    private var selectedMode: GameMode = LaunchOptions.forcedMode ?? Settings.shared.selectedMode
    private var modeLabel: SKLabelNode!
    private var modeDetailLabel: SKLabelNode!
    private var bestLabel: SKLabelNode!
    /// Horizontal room the mode card's labels have between the two arrows.
    private var modeTextWidth: CGFloat = 0
    private var statusLabel: SKLabelNode!
    private var walletLabel: SKLabelNode!
    private var previewBird: SKSpriteNode!
    private var dailyChallenge: DailyChallengeHelper.Challenge?
    private var statusToken: UUID?

    private let store = GameStore.shared
    private let settings = Settings.shared

    override func didMove(to view: SKView) {
        scaleMode = .resizeFill
        backgroundColor = TimeOfDay.day.skyColor

        buildBackdrop()
        buildTitle()
        buildModeSelector()
        buildActions()
        buildFooter()

        AudioManager.shared.start()

        statusToken = OnlineService.shared.observeStatus { [weak self] status in
            self?.statusLabel?.text = status.shortDescription.uppercased()
            self?.statusLabel?.fontColor = status.isOnline ? Palette.positive : Palette.secondaryText
        }
        OnlineService.shared.bootstrap()

        if LaunchOptions.isDemoMode {
            run(.sequence([.wait(forDuration: 1.6), .run { [weak self] in self?.startGame() }]))
        }

        // Pre-fetch today's challenge so tapping Daily is instant.
        Task { @MainActor [weak self] in
            let remote = await OnlineService.shared.todayChallenge()
            self?.dailyChallenge = DailyChallengeHelper.resolve(remote: remote)
            if self?.selectedMode == .daily { self?.refreshModeLabels() }
        }
    }

    override func willMove(from view: SKView) {
        if let statusToken { OnlineService.shared.removeObserver(statusToken) }
    }

    // MARK: - Layout

    private func buildBackdrop() {
        let world = SKNode()
        addChild(world)
        let parallax = ParallaxWorld(container: world, sceneSize: size)
        parallax.build(
            tint: .white,
            tintStrength: 0,
            reduceMotion: UIAccessibility.isReduceMotionEnabled
        )

        let dim = SKSpriteNode(color: SKColor(white: 0, alpha: 0.28), size: size)
        dim.position = CGPoint(x: size.width / 2, y: size.height / 2)
        dim.zPosition = ZPosition.hud - 1
        addChild(dim)
    }

    private func buildTitle() {
        let topInset = view?.safeAreaInsets.top ?? 0

        let title = SKLabelNode(fontNamed: Fonts.display)
        title.text = "FLAPPY BIRD"
        title.fontSize = 42
        title.fontColor = .white
        title.horizontalAlignmentMode = .center
        title.position = CGPoint(x: size.width / 2, y: size.height - topInset - 78)
        title.zPosition = ZPosition.hud
        addChild(title)

        let shadow = SKLabelNode(fontNamed: Fonts.display)
        shadow.text = title.text
        shadow.fontSize = title.fontSize
        shadow.fontColor = SKColor(white: 0, alpha: 0.35)
        shadow.position = CGPoint(x: title.position.x + 3, y: title.position.y - 3)
        shadow.zPosition = ZPosition.hud - 1
        addChild(shadow)

        let subtitle = SKLabelNode(fontNamed: Fonts.body)
        subtitle.text = "Swift · SpriteKit · optional cloud saves"
        subtitle.fontSize = 12
        subtitle.fontColor = Palette.secondaryText
        subtitle.position = CGPoint(x: size.width / 2, y: title.position.y - 26)
        subtitle.zPosition = ZPosition.hud
        addChild(subtitle)

        // A live bird wearing the selected skin, so the shop feels connected.
        let texture = SKTexture(imageNamed: "bird-01")
        texture.filteringMode = .nearest
        previewBird = SKSpriteNode(texture: texture)
        previewBird.setScale(2.4)
        previewBird.position = CGPoint(x: size.width / 2, y: title.position.y - 78)
        previewBird.zPosition = ZPosition.hud
        applySkinToPreview()
        addChild(previewBird)

        let bob = SKAction.sequence([
            .moveBy(x: 0, y: 10, duration: 0.5),
            .moveBy(x: 0, y: -10, duration: 0.5),
        ])
        bob.timingMode = .easeInEaseOut
        previewBird.run(.repeatForever(bob))

        let flap = SKAction.animate(
            with: ["bird-01", "bird-02"].map {
                let texture = SKTexture(imageNamed: $0)
                texture.filteringMode = .nearest
                return texture
            },
            timePerFrame: 0.18
        )
        previewBird.run(.repeatForever(flap))
    }

    private func applySkinToPreview() {
        previewBird.color = settings.selectedSkin.tint
        previewBird.colorBlendFactor = settings.selectedSkin.blend
    }

    private func buildModeSelector() {
        let centreY = size.height * 0.50
        let panelWidth = min(size.width - 48, 330)

        let panel = PanelNode(size: CGSize(width: panelWidth, height: 116))
        panel.position = CGPoint(x: size.width / 2, y: centreY)
        panel.zPosition = ZPosition.hud
        addChild(panel)

        modeLabel = SKLabelNode(fontNamed: Fonts.display)
        modeLabel.fontSize = 24
        modeLabel.fontColor = .white
        modeLabel.verticalAlignmentMode = .center
        modeLabel.position = CGPoint(x: 0, y: 24)
        panel.addChild(modeLabel)

        modeDetailLabel = SKLabelNode(fontNamed: Fonts.body)
        modeDetailLabel.fontSize = 12
        modeDetailLabel.fontColor = Palette.secondaryText
        modeDetailLabel.verticalAlignmentMode = .center
        modeDetailLabel.position = CGPoint(x: 0, y: 2)
        panel.addChild(modeDetailLabel)

        bestLabel = SKLabelNode(fontNamed: Fonts.body)
        bestLabel.fontSize = 13
        bestLabel.fontColor = Palette.accent
        bestLabel.verticalAlignmentMode = .center
        bestLabel.position = CGPoint(x: 0, y: -22)
        panel.addChild(bestLabel)

        // The arrows sit inside the card, not on its border: half the button plus
        // `MenuScene.arrowGutter` keeps a visible margin between the button edge
        // and the panel stroke at every width.
        let arrowCentre = panelWidth / 2 - MenuScene.arrowSize / 2 - MenuScene.arrowGutter

        let previous = ButtonNode(
            title: "◀",
            size: CGSize(width: MenuScene.arrowSize, height: MenuScene.arrowSize),
            fontSize: 18
        ) { [weak self] in
            self?.cycleMode(by: -1)
        }
        previous.position = CGPoint(x: -arrowCentre, y: -2)
        panel.addChild(previous)

        let next = ButtonNode(
            title: "▶",
            size: CGSize(width: MenuScene.arrowSize, height: MenuScene.arrowSize),
            fontSize: 18
        ) { [weak self] in
            self?.cycleMode(by: 1)
        }
        next.position = CGPoint(x: arrowCentre, y: -2)
        panel.addChild(next)

        // Everything between the arrows. The labels are centred on the card, so
        // the usable width is twice the distance from the centre to the nearer
        // arrow edge — not the panel width.
        modeTextWidth = 2 * (arrowCentre - MenuScene.arrowSize / 2 - MenuScene.arrowGutter)

        refreshModeLabels()
    }

    /// Side of the square mode arrows.
    private static let arrowSize: CGFloat = 40
    /// Clear space between an arrow's edge and the card's border.
    private static let arrowGutter: CGFloat = 10

    /// Shrink a label until it fits between the arrows.
    ///
    /// `SKLabelNode` neither wraps nor truncates on a single line — it just runs
    /// under whatever is beside it, which is how "The original rules, steady
    /// pace" ended up touching both arrows.
    private func fit(_ label: SKLabelNode, maxFontSize: CGFloat) {
        guard modeTextWidth > 0 else { return }
        label.fontSize = maxFontSize
        while label.fontSize > 9, label.frame.width > modeTextWidth {
            label.fontSize -= 1
        }
    }

    private func cycleMode(by delta: Int) {
        let modes = GameMode.selectable
        guard let index = modes.firstIndex(of: selectedMode) else { return }
        let next = (index + delta + modes.count) % modes.count
        selectedMode = modes[next]
        settings.selectedMode = selectedMode
        refreshModeLabels()
    }

    private func refreshModeLabels() {
        modeLabel.text = "\(selectedMode.symbol)  \(selectedMode.displayName.uppercased())"
        if selectedMode == .daily, let challenge = dailyChallenge {
            modeDetailLabel.text = challenge.summary
        } else {
            modeDetailLabel.text = selectedMode.subtitle
        }
        let best = store.profile.bestScore(for: selectedMode)
        bestLabel.text = best > 0 ? "BEST \(best)" : "NO SCORE YET"

        fit(modeLabel, maxFontSize: 24)
        fit(modeDetailLabel, maxFontSize: 12)
        fit(bestLabel, maxFontSize: 13)
    }

    private func buildActions() {
        let panelWidth = min(size.width - 48, 330)
        var y = size.height * 0.50 - 96

        let play = ButtonNode(
            title: "PLAY",
            size: CGSize(width: panelWidth, height: 54),
            fontSize: 26,
            // The primary action must read as a solid button over every sky
            // palette. The old 25%-alpha fill let pipes and clouds show through
            // it, making PLAY look disabled on brighter backgrounds.
            fillColor: Palette.positive,
            borderColor: Palette.positive
        ) { [weak self] in
            self?.startGame()
        }
        play.position = CGPoint(x: size.width / 2, y: y)
        play.zPosition = ZPosition.hud
        addChild(play)
        y -= 66

        // Four primary destinations in a compact 2x2 grid, with Settings kept
        // full-width below them so the five-item menu stays balanced.
        let columns: [(String, () -> Void)] = [
            ("LEADERBOARD", { [weak self] in self?.present(LeaderboardScene(size: self?.size ?? .zero)) }),
            ("ACHIEVEMENTS", { [weak self] in self?.present(AchievementsScene(size: self?.size ?? .zero)) }),
            ("SHOP", { [weak self] in self?.present(ShopScene(size: self?.size ?? .zero)) }),
            ("STATS", { [weak self] in self?.present(StatsScene(size: self?.size ?? .zero)) }),
        ]

        let buttonWidth = (panelWidth - 10) / 2
        for (index, column) in columns.enumerated() {
            let button = ButtonNode(
                title: column.0,
                size: CGSize(width: buttonWidth, height: 42),
                fontSize: 14,
                action: column.1
            )
            let row = index / 2
            let col = index % 2
            button.position = CGPoint(
                x: size.width / 2 + (col == 0 ? -(buttonWidth + 10) / 2 : (buttonWidth + 10) / 2),
                y: y - CGFloat(row) * 50
            )
            button.zPosition = ZPosition.hud
            addChild(button)
        }

        let settings = ButtonNode(
            title: "SETTINGS",
            size: CGSize(width: panelWidth, height: 42),
            fontSize: 14
        ) { [weak self] in
            self?.present(SettingsScene(size: self?.size ?? .zero))
        }
        settings.position = CGPoint(x: size.width / 2, y: y - 100)
        settings.zPosition = ZPosition.hud
        addChild(settings)
    }

    private func buildFooter() {
        let bottomInset = view?.safeAreaInsets.bottom ?? 0

        let wallet = CoinIcon.counter(amount: store.profile.wallet, radius: 8, fontSize: 16)
        wallet.node.position = CGPoint(x: 28, y: bottomInset + 26)
        wallet.node.zPosition = ZPosition.hud
        addChild(wallet.node)
        walletLabel = wallet.label

        statusLabel = SKLabelNode(fontNamed: Fonts.body)
        statusLabel.text = OnlineService.shared.status.shortDescription.uppercased()
        statusLabel.fontSize = 11
        statusLabel.fontColor = Palette.secondaryText
        statusLabel.horizontalAlignmentMode = .right
        statusLabel.position = CGPoint(x: size.width - 20, y: bottomInset + 26)
        statusLabel.zPosition = ZPosition.hud
        addChild(statusLabel)
    }

    // MARK: - Navigation

    private func startGame() {
        let scene = GameScene(size: size)
        scene.scaleMode = .resizeFill
        scene.mode = selectedMode
        if selectedMode == .daily {
            scene.dailyChallenge = dailyChallenge ?? DailyChallengeHelper.derive(for: DailyChallengeHelper.todayKey())
        }
        view?.presentScene(scene, transition: .doorway(withDuration: 0.5))
    }

    private func present(_ scene: SKScene) {
        scene.scaleMode = .resizeFill
        view?.presentScene(scene, transition: .push(with: .left, duration: 0.3))
    }
}
