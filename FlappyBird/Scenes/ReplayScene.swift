import SpriteKit
import UIKit

/// Plays a recorded run back.
///
/// Deliberately its own scene rather than an overlay on `GameScene`. The last
/// attempt at this drew a translucent second bird into the live game, where it
/// read as a rendering fault; a replay needs to announce itself as a replay,
/// which means its own screen, its own chrome and its own controls.
///
/// There is no physics here at all. The bird is positioned from the recording
/// and the pipes are interpolated along the path they travelled, so playback is
/// exact and cannot drift from what was recorded.
final class ReplayScene: SKScene {

    private let replay: Replay
    private var player: ReplayPlayer

    private var parallax: ParallaxWorld!
    private let worldNode = SKNode()
    private let pipesNode = SKNode()
    private var bird: SKSpriteNode!

    private var playPauseButton: ButtonNode!
    private var progressTrack: SKShapeNode!
    private var progressFill: SKShapeNode!
    private var timeLabel: SKLabelNode!

    /// Playback paused by the transport. Named apart from `SKScene.isPaused`,
    /// which pauses actions rather than the recording's clock.
    private var isHolding = false
    private var lastUpdate: TimeInterval = 0
    private var pipeNodes: [Int: SKNode] = [:]

    init(size: CGSize, replay: Replay) {
        self.replay = replay
        player = ReplayPlayer(replay: replay)
        super.init(size: size)
    }

    @available(*, unavailable)
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func didMove(to view: SKView) {
        scaleMode = .resizeFill
        backgroundColor = TimeOfDay.day.skyColor

        addChild(worldNode)
        worldNode.addChild(pipesNode)
        pipesNode.zPosition = ZPosition.pipes

        parallax = ParallaxWorld(container: worldNode, sceneSize: size)
        parallax.build(
            tint: TimeOfDay.day.worldTint,
            tintStrength: TimeOfDay.day.worldTintStrength,
            reduceMotion: UIAccessibility.isReduceMotionEnabled
        )

        buildBird()
        buildChrome()
        refresh()
    }

    private func buildBird() {
        let texture = SKTexture(imageNamed: "bird-01")
        texture.filteringMode = .nearest
        let node = SKSpriteNode(texture: texture)
        node.setScale(GameConfig.birdScale)
        node.color = Settings.shared.selectedSkin.tint
        node.colorBlendFactor = Settings.shared.selectedSkin.blend
        node.zPosition = ZPosition.bird
        node.position = CGPoint(x: size.width * 0.28, y: size.height / 2)
        addChild(node)
        bird = node

        let flap = SKAction.animate(
            with: ["bird-01", "bird-02", "bird-03", "bird-04"].map {
                let texture = SKTexture(imageNamed: $0)
                texture.filteringMode = .nearest
                return texture
            },
            timePerFrame: 0.12
        )
        node.run(.repeatForever(flap), withKey: "flap")
    }

    // MARK: - Chrome

    private func buildChrome() {
        let topInset = view?.safeAreaInsets.top ?? 0
        let bottomInset = view?.safeAreaInsets.bottom ?? 0
        let topY = size.height - topInset - 30

        // A replay must never be mistaken for live play.
        let bannerLabel = SKLabelNode(fontNamed: Fonts.display)
        bannerLabel.text = "▶  REPLAY"
        bannerLabel.fontSize = 18
        bannerLabel.fontColor = Palette.accent
        bannerLabel.verticalAlignmentMode = .center
        bannerLabel.horizontalAlignmentMode = .center

        let banner = SKShapeNode(
            rectOf: CGSize(width: bannerLabel.frame.width + 28, height: 32),
            cornerRadius: 16
        )
        banner.fillColor = Palette.panel.withAlphaComponent(0.92)
        banner.strokeColor = Palette.accent
        banner.lineWidth = 1.5
        banner.position = CGPoint(x: size.width / 2, y: topY)
        banner.zPosition = ZPosition.hud
        banner.isAccessibilityElement = true
        banner.accessibilityLabel = "Replay"
        banner.addChild(bannerLabel)
        addChild(banner)

        let summary = SKLabelNode(fontNamed: Fonts.body)
        summary.text = "\(replay.mode.displayName.uppercased()) · \(replay.score) pts · \(replay.coins)c"
        summary.fontSize = 13
        summary.fontColor = Palette.secondaryText
        summary.verticalAlignmentMode = .center
        summary.position = CGPoint(x: size.width / 2, y: topY - 30)
        summary.zPosition = ZPosition.hud
        addChild(summary)

        let back = ButtonNode(title: "‹", size: CGSize(width: 44, height: 40), fontSize: 26) { [weak self] in
            self?.close()
        }
        back.position = CGPoint(x: 36, y: topY)
        back.zPosition = ZPosition.hud
        addChild(back)

        // ── Transport, along the bottom ──────────────────────────────────────
        let controlsY = bottomInset + 46
        let trackWidth = min(size.width - 64, 320)

        // On its own panel. The controls sit over whatever the replay happens
        // to be showing — pale sand, in a run that ends near the ground — and a
        // thin progress bar and a small clock are unreadable against it.
        let tray = SKShapeNode(
            rectOf: CGSize(width: trackWidth + 36, height: 132),
            cornerRadius: 18
        )
        tray.fillColor = Palette.panel.withAlphaComponent(0.93)
        tray.strokeColor = Palette.panelBorder
        tray.lineWidth = 1.5
        tray.position = CGPoint(x: size.width / 2, y: controlsY + 28)
        tray.zPosition = ZPosition.hud - 1
        addChild(tray)

        progressTrack = SKShapeNode(
            rectOf: CGSize(width: trackWidth, height: 6),
            cornerRadius: 3
        )
        progressTrack.fillColor = SKColor(white: 1, alpha: 0.16)
        progressTrack.strokeColor = .clear
        progressTrack.position = CGPoint(x: size.width / 2, y: controlsY + 54)
        progressTrack.zPosition = ZPosition.hud
        addChild(progressTrack)

        progressFill = SKShapeNode(rectOf: CGSize(width: trackWidth, height: 6), cornerRadius: 3)
        progressFill.fillColor = Palette.accent
        progressFill.strokeColor = .clear
        progressFill.zPosition = ZPosition.hud + 1
        // Anchored left by moving the node, since SKShapeNode has no anchor.
        progressFill.position = progressTrack.position
        addChild(progressFill)

        timeLabel = SKLabelNode(fontNamed: Fonts.body)
        timeLabel.fontSize = 12
        timeLabel.fontColor = Palette.secondaryText
        timeLabel.verticalAlignmentMode = .center
        timeLabel.position = CGPoint(x: size.width / 2, y: controlsY + 34)
        timeLabel.zPosition = ZPosition.hud
        addChild(timeLabel)

        let buttonWidth = (trackWidth - 10) / 2
        playPauseButton = ButtonNode(
            title: "PAUSE",
            size: CGSize(width: buttonWidth, height: 44),
            fontSize: 17
        ) { [weak self] in
            self?.togglePlayback()
        }
        playPauseButton.position = CGPoint(x: size.width / 2 - (buttonWidth + 10) / 2, y: controlsY)
        playPauseButton.zPosition = ZPosition.hud
        addChild(playPauseButton)

        let restart = ButtonNode(
            title: "RESTART",
            size: CGSize(width: buttonWidth, height: 44),
            fontSize: 17
        ) { [weak self] in
            self?.restart()
        }
        restart.position = CGPoint(x: size.width / 2 + (buttonWidth + 10) / 2, y: controlsY)
        restart.zPosition = ZPosition.hud
        addChild(restart)
    }

    // MARK: - Transport

    private func togglePlayback() {
        isHolding.toggle()
        playPauseButton.title = isHolding ? "PLAY" : "PAUSE"
        worldNode.isPaused = isHolding
        bird.isPaused = isHolding
    }

    private func restart() {
        player.restart()
        if isHolding { togglePlayback() }
        refresh()
    }

    private func close() {
        let scene = ReplaysScene(size: size)
        scene.scaleMode = .resizeFill
        view?.presentScene(scene, transition: .push(with: .right, duration: 0.3))
    }

    // MARK: - Playback

    override func update(_ currentTime: TimeInterval) {
        let delta: TimeInterval = lastUpdate == 0 ? 0 : min(1.0 / 20.0, currentTime - lastUpdate)
        lastUpdate = currentTime

        guard !isHolding else { return }

        if player.hasFinished {
            // Hold on the final frame rather than snapping away, and offer the
            // obvious next action.
            if playPauseButton.title != "PLAY" {
                isHolding = true
                playPauseButton.title = "PLAY"
            }
            return
        }

        player.advance(by: delta)
        refresh()
    }

    /// Put every node where the current playback time says it should be.
    private func refresh() {
        if let pose = player.pose {
            bird.position = CGPoint(x: bird.position.x, y: CGFloat(pose.height) * size.height)
            bird.zRotation = CGFloat(pose.rotation)
        }

        var stillVisible: Set<Int> = []
        for entry in player.visibleObstacles() {
            stillVisible.insert(entry.index)
            let node = pipeNodes[entry.index] ?? makePipe(for: entry.obstacle, key: entry.index)
            node.position = CGPoint(x: CGFloat(entry.x) * size.width, y: 0)
        }

        for (key, node) in pipeNodes where !stillVisible.contains(key) {
            node.removeFromParent()
            pipeNodes.removeValue(forKey: key)
        }

        progressFill.xScale = max(0.0001, CGFloat(player.progress))
        let trackWidth = progressTrack.frame.width
        progressFill.position = CGPoint(
            x: progressTrack.position.x - trackWidth / 2 + trackWidth * CGFloat(player.progress) / 2,
            y: progressTrack.position.y
        )
        timeLabel.text = String(format: "%.1fs / %.1fs", player.time, replay.duration)
    }

    private func makePipe(for obstacle: Replay.Obstacle, key: Int) -> SKNode {
        let pair = PipePair.make(
            PipePair.Spec(
                gapCentre: CGFloat(obstacle.gapCentre) * size.height,
                gapHeight: CGFloat(obstacle.gapHeight) * size.height,
                sceneHeight: size.height,
                // A replay is a picture, not a game: no pickups to collect and
                // nothing to collide with.
                content: .none,
                tint: TimeOfDay.day.worldTint,
                tintStrength: TimeOfDay.day.worldTintStrength,
                moving: false
            )
        )
        pair.removePhysics()
        pipesNode.addChild(pair)
        pipeNodes[key] = pair
        return pair
    }
}
